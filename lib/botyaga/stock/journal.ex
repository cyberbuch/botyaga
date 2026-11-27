defmodule Botyaga.Stock.Journal do
  @moduledoc """
  Осчетоводяване след преизчисление: маха стария себестойностен ред от
  фактурата и презаписва записите на производство и ръчно изписване.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Invoicing, Journal, Repo}
  alias Botyaga.Journal.{Entry, Line}
  alias Botyaga.Production.{Order, OrderLine}
  alias Botyaga.Stock.{Kit, MaterialIssue, MaterialIssueLine, Rules}

  def strip_legacy(company_id) do
    entries =
      Repo.all(
        from(e in Entry,
          join: i in Invoicing.Invoice,
          on: e.document_id == i.id,
          where:
            e.company_id == ^company_id and i.company_id == ^company_id and i.direction == "out" and
              i.status == "posted" and
              i.document_type in ["01", "11"] and e.document_type in ["01", "11"],
          select: e.id
        )
      )

    Enum.each(entries, fn id ->
      lines = Repo.all(from(l in Line, where: l.entry_id == ^id))

      debit_acc =
        lines
        |> Enum.filter(&(&1.direction == "debit"))
        |> Enum.map(& &1.account_id)
        |> MapSet.new()

      credit_acc =
        lines
        |> Enum.filter(&(&1.direction == "credit"))
        |> Enum.map(& &1.account_id)
        |> MapSet.new()

      dual = MapSet.intersection(debit_acc, credit_acc)

      {drop_amt, drop_id} =
        Enum.reduce(lines, {[], []}, fn line, {amts, ids} ->
          if line.direction == "debit" and MapSet.member?(dual, line.account_id) do
            {amts ++ [Dec.or0(line.amount)], ids ++ [line.id]}
          else
            {amts, ids}
          end
        end)

      {_drop_amt, drop_id} =
        Enum.reduce(lines, {drop_amt, drop_id}, fn line, {amts, ids} ->
          if line.direction != "credit" or MapSet.member?(dual, line.account_id) or
               Dec.or0(line.vat_amount) != 0 do
            {amts, ids}
          else
            amt = Dec.or0(line.amount)

            case Enum.find_index(amts, &(&1 == amt)) do
              nil -> {amts, ids}
              pos -> {List.delete_at(amts, pos), ids ++ [line.id]}
            end
          end
        end)

      Enum.each(drop_id, fn lid -> Repo.delete_all(from(l in Line, where: l.id == ^lid)) end)
    end)
  end

  def rewrite(company_id, products, books, warnings) do
    rules = Rules.load(company_id)

    kit_ids =
      MapSet.new(Repo.all(from(k in Kit, where: k.company_id == ^company_id, select: k.id)))

    warnings = rewrite_production(company_id, products, rules, books, warnings, kit_ids)
    warnings = rewrite_kits(company_id, products, books, warnings, kit_ids)
    rewrite_material(company_id, rules, books, warnings)
  end

  # Комплектоване: стойността на съставките се прехвърля към комплекта (без 611).
  defp rewrite_kits(company_id, products, books, warnings, kit_ids) do
    Enum.reduce(books.prods, warnings, fn order, warnings ->
      if not MapSet.member?(kit_ids, order.id) do
        warnings
      else
        case Map.get(products, order.output_id) do
          nil ->
            warnings

          out ->
            costs = Enum.filter(books.made, &(&1.doc == order.id))
            total = Enum.reduce(costs, 0, &(&2 + &1.cost))

            sides =
              Enum.flat_map(costs, fn c ->
                case Map.get(products, c.product) do
                  nil ->
                    []

                  comp ->
                    with {:ok, inv} <- account_by_id(comp.inventory, company_id) do
                      [%{account: inv, direction: "credit", amount: Dec.money(c.cost)}]
                    else
                      _ -> []
                    end
                end
              end)

            sides =
              if total != 0 do
                with {:ok, inv} <- account_by_id(out.inventory, company_id) do
                  [%{account: inv, direction: "debit", amount: Dec.money(total)} | sides]
                else
                  _ -> sides
                end
              else
                sides
              end

            if sides == [] do
              warnings
            else
              entry =
                write_fresh(
                  company_id,
                  "kit",
                  order.id,
                  order.number,
                  order.date,
                  "Комплектоване #{order.number}",
                  sides
                )

              Repo.update_all(from(k in Kit, where: k.id == ^order.id),
                set: [cost: Dec.money(total), journal_entry_id: entry]
              )

              warnings
            end
        end
      end
    end)
  end

  defp rewrite_production(company_id, products, rules, books, warnings, kit_ids) do
    Enum.reduce(books.prods, warnings, fn order, warnings ->
      if MapSet.member?(kit_ids, order.id) do
        warnings
      else
        case Map.get(products, order.output_id) do
          nil ->
            warnings

          out ->
            case Rules.pair(rules, "production", out.inventory, out.revenue) do
              nil ->
                warnings ++ ["няма правило за продукция за #{out.name}"]

              rule ->
                if rule.clearing_account_id <= 0 do
                  warnings ++ ["правилото за продукция няма междинна сметка (#{out.name})"]
                else
                  costs = Enum.filter(books.made, &(&1.doc == order.id))

                  {sides, total, warnings, ok} =
                    production_sides(company_id, products, rules, rule, costs, warnings)

                  if ok do
                    sides =
                      if total != 0 do
                        with {:ok, clearing} <-
                               account_by_id(rule.clearing_account_id, company_id),
                             {:ok, inv} <- account_by_id(out.inventory, company_id) do
                          sides ++
                            [
                              %{account: inv, direction: "debit", amount: Dec.money(total)},
                              %{account: clearing, direction: "credit", amount: Dec.money(total)}
                            ]
                        else
                          _ -> sides
                        end
                      else
                        sides
                      end

                    entry =
                      write_fresh(
                        company_id,
                        "production",
                        order.id,
                        order.number,
                        order.date,
                        "Производство #{order.number}",
                        sides
                      )

                    store_prod_lines(order.id, costs)

                    Repo.update_all(from(o in Order, where: o.id == ^order.id),
                      set: [material_cost: Dec.money(total), journal_entry_id: entry]
                    )

                    warnings
                  else
                    warnings
                  end
                end
            end
        end
      end
    end)
  end

  defp production_sides(company_id, products, rules, rule, costs, warnings) do
    Enum.reduce_while(costs, {[], 0, warnings, true}, fn cost, {sides, total, warnings, _ok} ->
      case Map.get(products, cost.product) do
        nil ->
          {:cont, {sides, total, warnings, true}}

        mat ->
          if Rules.material_inventory(rules, mat.inventory) == nil do
            {:halt,
             {sides, total, warnings ++ ["няма правило за материал за #{mat.name}"], false}}
          else
            if cost.cost == 0 do
              {:cont, {sides, total, warnings, true}}
            else
              with {:ok, clearing} <- account_by_id(rule.clearing_account_id, company_id),
                   {:ok, inv} <- account_by_id(mat.inventory, company_id) do
                {:cont,
                 {sides ++
                    [
                      %{account: clearing, direction: "debit", amount: Dec.money(cost.cost)},
                      %{account: inv, direction: "credit", amount: Dec.money(cost.cost)}
                    ], total + cost.cost, warnings, true}}
              else
                _ -> {:halt, {sides, total, warnings, false}}
              end
            end
          end
      end
    end)
  end

  defp store_prod_lines(order_id, costs) do
    lines = Repo.all(from(l in OrderLine, where: l.order_id == ^order_id, order_by: [asc: l.id]))

    Enum.reduce(lines, costs, fn line, left ->
      case Enum.find_index(left, &(&1.product == line.product_id)) do
        nil ->
          Repo.update_all(from(l in OrderLine, where: l.id == ^line.id),
            set: [unit_cost: "0.000000", amount: "0.00"]
          )

          left

        pos ->
          c = Enum.at(left, pos)
          unit = if c.qty > 0, do: Dec.text(Dec.div(c.cost, c.qty) || 0, 6), else: "0.000000"

          Repo.update_all(from(l in OrderLine, where: l.id == ^line.id),
            set: [unit_cost: unit, amount: Dec.money(c.cost)]
          )

          List.delete_at(left, pos)
      end
    end)
  end

  defp rewrite_material(company_id, rules, books, warnings) do
    Enum.reduce(books.uses, warnings, fn doc, warnings ->
      lines =
        Repo.all(
          from(l in MaterialIssueLine,
            where: l.doc_id == ^doc.id,
            order_by: [asc: l.line_no, asc: l.id]
          )
        )

      left = Enum.filter(books.spent, &(&1.doc == doc.id))

      {sides, updates, warnings, skip, _left} =
        Enum.reduce_while(lines, {[], [], warnings, false, left}, fn line,
                                                                     {sides, updates, warnings,
                                                                      _skip, left} ->
          if not Rules.material_line_allowed(
               company_id,
               rules,
               line.product_id,
               line.inventory_account_id,
               line.account_id
             ) do
            {:halt,
             {sides, updates, warnings ++ ["няма правило за материал по документ #{doc.number}"],
              true, left}}
          else
            {cost, left} =
              case Enum.find_index(left, &(&1.product == line.product_id)) do
                nil -> {0, left}
                pos -> {Enum.at(left, pos).cost, List.delete_at(left, pos)}
              end

            q = Dec.or0(line.quantity)
            unit = if q > 0, do: Dec.text(Dec.div(cost, q) || 0, 6), else: "0.000000"
            updates = updates ++ [{line.id, unit, Dec.money(cost)}]

            if cost != 0 do
              with {:ok, debit} <- account_by_id(line.account_id, company_id),
                   {:ok, credit} <- account_by_id(line.inventory_account_id, company_id) do
                {:cont,
                 {sides ++
                    [
                      %{account: debit, direction: "debit", amount: Dec.money(cost)},
                      %{account: credit, direction: "credit", amount: Dec.money(cost)}
                    ], updates, warnings, false, left}}
              else
                _ -> {:halt, {sides, updates, warnings, true, left}}
              end
            else
              {:cont, {sides, updates, warnings, false, left}}
            end
          end
        end)

      if skip do
        warnings
      else
        entry =
          write_fresh(
            company_id,
            "material_issue",
            doc.id,
            doc.number,
            doc.date,
            "Изписване #{doc.number}",
            sides
          )

        Enum.each(updates, fn {id, unit, amount} ->
          Repo.update_all(from(l in MaterialIssueLine, where: l.id == ^id),
            set: [unit_cost: unit, amount: amount]
          )
        end)

        Repo.update_all(from(d in MaterialIssue, where: d.id == ^doc.id),
          set: [journal_entry_id: entry]
        )

        warnings
      end
    end)
  end

  defp write_fresh(company_id, doc_type, doc_id, number, date, desc, sides) do
    old =
      Repo.all(
        from(e in Entry,
          where:
            e.company_id == ^company_id and e.document_type == ^doc_type and
              e.document_id == ^doc_id,
          select: e.id
        )
      )

    Enum.each(old, &Journal.wipe/1)

    if sides == [] do
      0
    else
      {:ok, entry} =
        Journal.write_entry(
          company_id,
          date,
          doc_type,
          doc_id,
          number,
          desc,
          0,
          "",
          month_of(date),
          sides
        )

      entry
    end
  end

  defp account_by_id(id, company_id) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company_id) do
      nil -> {:error, {422, "липсва сметка с id #{id}"}}
      account -> {:ok, account}
    end
  end

  defp month_of(date), do: if(String.length(date) >= 7, do: String.slice(date, 0, 7), else: date)
end

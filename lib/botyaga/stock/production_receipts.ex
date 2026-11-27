defmodule Botyaga.Stock.ProductionReceipts do
  @moduledoc """
  Ръчен приход на продукция за месец (производство по поръчка — без рецепта).

  Таб 1 "Произведено": продаденото по КТ 701 за месеца (фактури за продажба),
  натрупаната стойност в 611 (себестойност на продаденото) и ръчно поле
  „наличност" в края на месеца — произведено = продадено + наличност.
  Таб 2 "Разпределение 612": натрупаните непреки разходи по 612 (без 61201)
  се разпределят пропорционално на произведената стойност по артикул.
  Таб 3 "Записи": при потвърждаване се пише един запис —
  ДТ 303 КТ 611 (приход на продукция), ДТ 303 КТ 612 (разпределение) и
  ДТ 701 КТ 303 за продаденото (в 303 вече е пълната стойност).

  Сметките се вземат от артикула: 303 = inventory_account_id,
  701 = revenue_account_id, 611 = expense_account_id. Префиксите 611/612
  в прегледа са параметри (по подразбиране "611"/"612", изключва се "61201").
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Dec, Journal, Params, Periods, Repo}
  alias Botyaga.Catalog.Account
  alias Botyaga.Invoicing.{Invoice, InvoiceLine}
  alias Botyaga.Journal.Entry

  alias Botyaga.Stock.{
    ProductionReceipt,
    ProductionReceiptAllocation,
    ProductionReceiptLine,
    Rules
  }

  @doc_type "production_receipt"

  ## Списък и преглед

  def index(company_id) do
    stamps = Audit.stamps_for(company_id, @doc_type)

    Repo.all(
      from(d in ProductionReceipt, where: d.company_id == ^company_id, order_by: [desc: d.id])
    )
    |> Enum.map(fn d -> d |> one(false) |> Audit.attach_stamp(Map.get(stamps, d.id)) end)
  end

  def show(company_id, id) do
    with {:ok, doc} <- fetch(company_id, id) do
      {:ok, with_audit(company_id, doc)}
    end
  end

  @doc """
  Таб 1 преди създаване: продаденото по КТ 701 за месеца, натрупаната
  стойност в 611 и натрупаните непреки разходи по 612 за разпределение.
  """
  def preview(company_id, params) do
    with {:ok, month} <- month_param(params) do
      products = products_map(company_id)
      sold = sold_by_product(company_id, month, products)
      expense_total = expense_total(company_id, month, params)
      total_sold = sold |> Enum.reduce(0, fn {_pid, s}, acc -> acc + s.qty end)
      unit = if total_sold > 0, do: Dec.div(expense_total, total_sold) || 0, else: 0

      lines =
        sold
        |> Enum.map(fn {pid, %{qty: q, revenue: rev}} ->
          p = Map.fetch!(products, pid)

          %{
            product_id: pid,
            product_name: p.name,
            code: p.code,
            unit: p.unit,
            sold_quantity: Dec.qty(q),
            sold_revenue: Dec.money(rev),
            sold_amount: Dec.money(Dec.mul(q, unit)),
            unit_cost: Dec.text(unit, 6),
            inventory_account_id: p.inventory_account_id,
            revenue_account_id: p.revenue_account_id,
            expense_account_id: expense_account(company_id, p)
          }
        end)
        |> Enum.sort_by(& &1.product_name)

      %{
        month: month,
        doc_date: last_day(month),
        lines: lines,
        expense_total: Dec.money(expense_total),
        expense_turnover:
          turnover(company_id, month, prefix(params, "expense_prefix", "611"), ""),
        indirect: indirect_json(company_id, month, params)
      }
      |> then(&{:ok, &1})
    end
  end

  ## CRUD

  def create(company_id, sub, params) do
    with {:ok, month} <- month_param(params),
         {:ok, lines} <- build_lines(company_id, month, params) do
      date = last_day(month)
      notes = string(params, "notes")

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.insert!(%ProductionReceipt{
              company_id: company_id,
              doc_date: date,
              month: month,
              status: "draft",
              notes: notes,
              journal_entry_id: 0,
              wip_end_mode: pick(params, "wip_end_mode", "amount"),
              wip_end_value: pick(params, "wip_end_value", "0")
            })

          doc = Repo.update!(Ecto.Changeset.change(doc, number: "ПР-#{doc.id}"))
          insert_lines(doc.id, lines)
          doc
        end)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "create",
        "Създаден ръчен приход на продукция #{doc.number} за #{month}",
        "",
        "0.00",
        nil,
        one(doc, true)
      )

      show(company_id, doc.id)
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- draft(doc),
         {:ok, lines} <- build_lines(company_id, doc.month, params) do
      notes = pick(params, "notes", doc.notes)
      before = one(doc, true)

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.update!(
              Ecto.Changeset.change(doc,
                notes: notes,
                wip_end_mode: pick(params, "wip_end_mode", doc.wip_end_mode),
                wip_end_value: pick(params, "wip_end_value", doc.wip_end_value)
              )
            )

          Repo.delete_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id))
          Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))
          insert_lines(doc.id, lines)
          doc
        end)

      after_value = one(doc, true)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "update",
        "Редактиран ръчен приход на продукция #{doc.number} за #{doc.month}",
        doc_total(before),
        doc_total(after_value),
        before,
        after_value
      )

      show(company_id, doc.id)
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- draft(doc) do
      before = one(doc, true)
      Repo.delete_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id))
      Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))
      Repo.delete!(doc)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "delete",
        "Изтрит ръчен приход на продукция #{doc.number} за #{doc.month}",
        doc_total(before),
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  ## Потвърждаване / връщане

  def confirm(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- draft(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date),
         :ok <- no_other_confirmed(company_id, doc),
         lines = lines_of(doc.id),
         :ok <- not_empty(lines),
         :ok <- lines_ready(company_id, lines),
         recomputed = recompute_lines(company_id, doc.month, lines, doc),
         :ok <- values_present(recomputed),
         {:ok, allocs, indirect_total} <- allocations(company_id, doc.month, recomputed, %{}),
         {:ok, sides, totals} <- sides(company_id, recomputed, allocs, indirect_total) do
      {:ok, _entry_id} =
        Repo.transaction(fn ->
          entry_id =
            if sides == [] do
              0
            else
              {:ok, eid} =
                Journal.write_entry(
                  company_id,
                  doc.doc_date,
                  @doc_type,
                  doc.id,
                  doc.number,
                  "Ръчен приход на продукция #{doc.month} (#{doc.number})",
                  0,
                  "",
                  doc.month,
                  sides
                )

              eid
            end

          persist_lines(doc.id, recomputed, allocs)
          insert_allocations(doc.id, allocs)

          Repo.update!(
            Ecto.Changeset.change(doc, status: "confirmed", journal_entry_id: entry_id)
          )

          entry_id
        end)

      {:ok, after_doc} = fetch(company_id, id)
      after_value = one(after_doc, true)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        after_doc.number,
        "post",
        "Потвърден ръчен приход на продукция #{after_doc.number} за #{doc.month}, сума #{totals.total}",
        "0.00",
        totals.total,
        one(doc, true),
        after_value
      )

      {:ok, with_audit(company_id, after_doc)}
    end
  end

  def unpost(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- confirmed(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date) do
      before = one(doc, true)
      old_tot = doc_total(before)
      Journal.wipe(doc.journal_entry_id)

      Repo.transaction(fn ->
        Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))

        Repo.update_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id),
          set: [allocated_amount: "0.00", writeoff_amount: "0.00"]
        )

        Repo.update!(Ecto.Changeset.change(doc, status: "draft", journal_entry_id: 0))
      end)

      {:ok, after_doc} = fetch(company_id, id)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        after_doc.number,
        "unpost",
        "Върнат в чернова ръчен приход #{after_doc.number} за #{doc.month}, стара сума #{old_tot}",
        old_tot,
        "0.00",
        before,
        one(after_doc, true)
      )

      {:ok, with_audit(company_id, after_doc)}
    end
  end

  ## Таб 1 — продадено по КТ 701 за месеца

  defp sold_by_product(company_id, month, products) do
    rows =
      Repo.all(
        from(i in Invoice,
          join: l in InvoiceLine,
          on: l.invoice_id == i.id,
          where:
            i.company_id == ^company_id and i.status == "posted" and i.direction == "out" and
              i.document_type in ["01", "11"] and l.product_id > 0 and
              like(i.issue_date, ^"#{month}%"),
          select: {l.product_id, l.quantity, l.net_amount}
        )
      )

    Enum.reduce(rows, %{}, fn {pid, q, net}, acc ->
      if Map.has_key?(products, pid) do
        p = Map.fetch!(products, pid)

        if p.inventory_account_id > 0 and p.revenue_account_id > 0 do
          cur = Map.get(acc, pid, %{qty: 0, revenue: 0})
          Map.put(acc, pid, %{qty: cur.qty + Dec.or0(q), revenue: cur.revenue + Dec.or0(net)})
        else
          acc
        end
      else
        acc
      end
    end)
  end

  ## Редове на документа

  defp products_map(company_id) do
    Repo.all(from(p in Catalog.Product, where: p.company_id == ^company_id))
    |> Map.new(&{&1.id, &1})
  end

  # Стойността на произведеното идва от натрупаното в 611 за месеца:
  # единична цена = 611 / общо произведено; по ред = произведено × единична.
  defp build_lines(company_id, month, params) do
    products = products_map(company_id)
    sold = sold_by_product(company_id, month, products)

    arr =
      case Map.get(params, "lines") do
        list when is_list(list) -> list
        _ -> []
      end

    ending =
      Enum.reduce(arr, %{}, fn l, acc ->
        pid = Params.integer(l, "product_id") || 0

        case qty_of(Map.get(l, "ending_quantity")) do
          {:ok, q} ->
            Map.put(acc, pid, {q, pick(l, "coefficient", "1"), pick(l, "manual_amount", "")})

          _ ->
            acc
        end
      end)

    ids =
      (Map.keys(sold) ++ Map.keys(ending))
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(products, &1))
      |> Enum.sort()

    rows =
      Enum.reduce(ids, [], fn pid, acc ->
        p = Map.fetch!(products, pid)
        s = Map.get(sold, pid, %{qty: 0, revenue: 0})
        {end_qty, coef, manual} = Map.get(ending, pid, {0, "1", ""})
        acc ++ [{p, s.qty, end_qty, coef, manual}]
      end)

    case Enum.reduce_while(rows, {:ok, []}, fn {p, sold_qty, end_qty, coef, manual}, {:ok, acc} ->
           case product_ok(company_id, p) do
             :ok ->
               {:cont,
                {:ok,
                 acc ++
                   [
                     %{
                       id: p.id,
                       product: p,
                       sold_quantity: sold_qty,
                       ending_quantity: end_qty,
                       quantity: sold_qty + end_qty,
                       coefficient: coef,
                       manual_amount: manual
                     }
                   ]}}

             {:error, _} = err ->
               {:halt, err}
           end
         end) do
      {:ok, []} ->
        {:error, {422, "няма артикули за месеца — проверете продажбите по КТ 701"}}

      {:ok, prepared} ->
        expense_total = expense_total(company_id, month, params)
        available = expense_total - wip_end(params, expense_total)
        amounts = line_amounts(prepared, available)

        {:ok,
         Enum.zip(prepared, amounts)
         |> Enum.map(fn {r, amount} ->
           p = r.product
           unit = if r.quantity > 0, do: Dec.div(amount, r.quantity) || 0, else: 0

           %{
             product_id: p.id,
             sold_quantity: r.sold_quantity,
             sold_amount: Dec.mul(r.sold_quantity, unit),
             ending_quantity: r.ending_quantity,
             quantity: r.quantity,
             unit_cost: unit,
             amount: amount,
             coefficient: r.coefficient,
             manual_amount: r.manual_amount,
             inventory_account_id: p.inventory_account_id,
             revenue_account_id: p.revenue_account_id,
             expense_account_id: expense_account(company_id, p)
           }
         end)}

      {:error, _} = err ->
        err
    end
  end

  # При потвърждаване стойностите се преизчисляват от текущия оборот на 611.
  defp recompute_lines(company_id, month, lines, doc) do
    expense_total = expense_total(company_id, month, %{})
    wip = %{"wip_end_mode" => doc.wip_end_mode, "wip_end_value" => doc.wip_end_value}
    available = expense_total - wip_end(wip, expense_total)

    rows =
      Enum.map(lines, fn l ->
        %{
          id: l.product_id,
          quantity: Dec.or0(l.sold_quantity) + Dec.or0(l.ending_quantity),
          coefficient: l.coefficient,
          manual_amount: l.manual_amount
        }
      end)

    amounts = line_amounts(rows, available)

    Enum.zip(lines, amounts)
    |> Enum.map(fn {l, amount} ->
      sold = Dec.or0(l.sold_quantity)
      end_qty = Dec.or0(l.ending_quantity)
      qty = sold + end_qty
      unit = if qty > 0, do: Dec.div(amount, qty) || 0, else: 0

      %{
        product_id: l.product_id,
        sold_quantity: sold,
        sold_amount: Dec.mul(sold, unit),
        ending_quantity: end_qty,
        quantity: qty,
        unit_cost: unit,
        amount: amount,
        coefficient: l.coefficient,
        manual_amount: l.manual_amount,
        inventory_account_id: l.inventory_account_id,
        revenue_account_id: l.revenue_account_id,
        expense_account_id: l.expense_account_id
      }
    end)
  end

  # Незавършено производство: част от 611, която остава за следващия месец.
  defp wip_end(src, available) do
    case pick(src, "wip_end_mode", "amount") do
      "percent" ->
        Dec.div(Dec.mul(available, Dec.or0(pick(src, "wip_end_value", "0"))), 100 * Dec.scale()) ||
          0

      _ ->
        Dec.or0(pick(src, "wip_end_value", "0"))
    end
  end

  # Разпределение: ръчна сума има предност; останалото по количество×коефициент.
  defp line_amounts(rows, available) do
    manual_sum =
      Enum.reduce(rows, 0, fn r, a ->
        a + if(r.manual_amount != "", do: Dec.or0(r.manual_amount), else: 0)
      end)

    rest = available - manual_sum
    auto = Enum.filter(rows, &(&1.manual_amount == ""))
    weight = fn r -> Dec.mul(r.quantity, Dec.or0(r.coefficient)) end
    tw = Enum.reduce(auto, 0, &(&2 + weight.(&1)))

    auto_map =
      if tw > 0 do
        list = Enum.map(auto, fn r -> {r.id, Dec.div(Dec.mul(rest, weight.(r)), tw) || 0} end)
        sum = Enum.reduce(list, 0, &(&2 + elem(&1, 1)))
        diff = rest - sum

        list =
          case list do
            [] ->
              []

            l ->
              {lid, lv} = List.last(l)
              List.replace_at(l, length(l) - 1, {lid, lv + diff})
          end

        Map.new(list)
      else
        Map.new(auto, &{&1.id, 0})
      end

    Enum.map(rows, fn r ->
      if r.manual_amount != "", do: Dec.or0(r.manual_amount), else: Map.get(auto_map, r.id, 0)
    end)
  end

  # Натрупаната стойност в 611 за месеца (нетен дебитен оборот по префикс 611).
  defp expense_total(company_id, month, params) do
    prefix = prefix(params, "expense_prefix", "611")

    net_turnover(company_id, month, prefix, "")
    |> Enum.reduce(0, fn a, s -> s + a.amount end)
  end

  defp product_ok(company_id, p) do
    cond do
      p.inventory_account_id <= 0 ->
        {:error, {422, "артикулът #{p.name} няма сметка за наличност (303)"}}

      p.revenue_account_id <= 0 ->
        {:error, {422, "артикулът #{p.name} няма приходна сметка (701)"}}

      expense_account(company_id, p) <= 0 ->
        {:error, {422, "артикулът #{p.name} няма разходна сметка (611)"}}

      true ->
        :ok
    end
  end

  # 611: от артикула, иначе clearing сметката от правилото за продукция
  defp expense_account(company_id, p) do
    if p.expense_account_id > 0 do
      p.expense_account_id
    else
      case Rules.pair(
             Rules.load(company_id),
             "production",
             p.inventory_account_id,
             p.revenue_account_id
           ) do
        %{clearing_account_id: c} when c > 0 -> c
        _ -> 0
      end
    end
  end

  defp insert_lines(doc_id, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, no} ->
      Repo.insert!(%ProductionReceiptLine{
        doc_id: doc_id,
        line_no: no,
        product_id: line.product_id,
        sold_quantity: Dec.qty(line.sold_quantity),
        sold_amount: Dec.money(line.sold_amount),
        ending_quantity: Dec.qty(line.ending_quantity),
        quantity: Dec.qty(line.quantity),
        unit_cost: Dec.text(line.unit_cost, 6),
        amount: Dec.money(line.amount),
        allocated_amount: "0.00",
        writeoff_amount: "0.00",
        inventory_account_id: line.inventory_account_id,
        revenue_account_id: line.revenue_account_id,
        expense_account_id: line.expense_account_id,
        coefficient: line.coefficient,
        manual_amount: line.manual_amount
      })
    end)
  end

  ## Таб 2 — разпределение на натрупаните непреки разходи по 612

  # Числов (скалиран) списък за разпределение; в preview се форматира.
  defp indirect_accounts(company_id, month, params) do
    prefix = prefix(params, "indirect_prefix", "612")
    exclude = prefix(params, "indirect_exclude", "61201")
    net_turnover(company_id, month, prefix, exclude) |> Enum.filter(&(&1.amount > 0))
  end

  defp indirect_json(company_id, month, params) do
    indirect_accounts(company_id, month, params)
    |> Enum.map(fn a ->
      %{account_id: a.account_id, number: a.number, name: a.name, amount: Dec.money(a.amount)}
    end)
  end

  # Нетен оборот (дебит - кредит) по сметки с префикс за месеца, само положителен.
  defp turnover(company_id, month, prefix, exclude) do
    net_turnover(company_id, month, prefix, exclude)
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.map(fn a ->
      %{account_id: a.account_id, number: a.number, name: a.name, amount: Dec.money(a.amount)}
    end)
    |> Enum.sort_by(& &1.number)
  end

  defp net_turnover(company_id, month, prefix, exclude) do
    rows =
      Repo.all(
        from(e in Entry,
          join: l in Botyaga.Journal.Line,
          on: l.entry_id == e.id,
          join: a in Account,
          on: a.id == l.account_id,
          where:
            e.company_id == ^company_id and like(e.entry_date, ^"#{month}%") and
              like(a.number, ^"#{prefix}%"),
          select: {a.id, a.number, a.name, l.direction, l.amount}
        )
      )

    rows
    |> Enum.reject(fn {_id, num, _name, _dir, _amt} ->
      exclude != "" and String.starts_with?(num, exclude)
    end)
    |> Enum.reduce(%{}, fn {id, num, name, dir, amt}, acc ->
      v = if dir == "debit", do: Dec.or0(amt), else: -Dec.or0(amt)
      cur = Map.get(acc, id, %{account_id: id, number: num, name: name, amount: 0})
      Map.put(acc, id, %{cur | amount: cur.amount + v})
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.number)
  end

  # Разпределение пропорционално на произведената стойност (amount) по ред.
  defp allocations(company_id, month, lines, params) do
    indirect = indirect_accounts(company_id, month, params)
    total_base = lines |> Enum.reduce(0, fn l, s -> s + l.amount end)

    {allocs, indirect_total} =
      Enum.reduce(indirect, {[], 0}, fn acc, {rows_acc, tot} ->
        amt = acc.amount
        per_line = split_share(amt, total_base, lines)

        rows =
          per_line
          |> Enum.map(fn {line, share} ->
            %{
              product_id: line.product_id,
              account_id: acc.account_id,
              base_amount: line.amount,
              amount: share
            }
          end)
          |> Enum.filter(&(&1.amount != 0))

        {rows_acc ++ rows, tot + amt}
      end)

    {:ok, allocs, indirect_total}
  end

  # Пропорционално разпределение с закръгляне до стотинки; последният ред поема остатъка.
  defp split_share(total, base, lines) do
    with_base = Enum.filter(lines, &(&1.amount > 0))

    if base <= 0 or with_base == [] do
      Enum.map(lines, &{&1, 0})
    else
      rounded =
        Enum.reduce(with_base, [], fn line, acc ->
          raw = Dec.mul(total, Dec.div(line.amount, base) || 0) || 0
          acc ++ [{line, round_to_money(raw)}]
        end)

      sum = Enum.reduce(rounded, 0, fn {_l, r}, s -> s + r end)
      diff = round_to_money(total) - sum

      rounded =
        if diff != 0 and rounded != [] do
          {last_line, last_r} = List.last(rounded)
          List.replace_at(rounded, length(rounded) - 1, {last_line, last_r + diff})
        else
          rounded
        end

      by_pid = Map.new(rounded, fn {l, r} -> {l.product_id, r} end)
      Enum.map(lines, fn l -> {l, Map.get(by_pid, l.product_id, 0)} end)
    end
  end

  defp round_to_money(v), do: v |> Dec.money() |> Dec.or0()

  ## Таб 3 — journal запис при потвърждаване

  defp sides(company_id, lines, allocs, _indirect_total) do
    with {:ok, accounts} <- accounts_by_id(company_id, lines, allocs) do
      receipt =
        Enum.flat_map(lines, fn l ->
          amt = l.amount

          if amt > 0 do
            [
              %{
                account: Map.fetch!(accounts, l.inventory_account_id),
                direction: "debit",
                amount: Dec.money(amt)
              },
              %{
                account: Map.fetch!(accounts, l.expense_account_id),
                direction: "credit",
                amount: Dec.money(amt)
              }
            ]
          else
            []
          end
        end)

      dist =
        Enum.flat_map(allocs, fn a ->
          amt = a.amount

          if amt > 0 do
            line = Enum.find(lines, &(&1.product_id == a.product_id))

            [
              %{
                account: Map.fetch!(accounts, line.inventory_account_id),
                direction: "debit",
                amount: Dec.money(amt)
              },
              %{
                account: Map.fetch!(accounts, a.account_id),
                direction: "credit",
                amount: Dec.money(amt)
              }
            ]
          else
            []
          end
        end)

      alloc_by_product =
        Enum.reduce(allocs, %{}, fn a, acc ->
          Map.update(acc, a.product_id, a.amount, &(&1 + a.amount))
        end)

      writeoff =
        Enum.flat_map(lines, fn l ->
          q = l.quantity
          sold = l.sold_quantity
          full = l.amount + Map.get(alloc_by_product, l.product_id, 0)
          w = if q > 0 and sold > 0, do: Dec.mul(sold, Dec.div(full, q) || 0) || 0, else: 0
          w = round_to_money(w)

          if w > 0 do
            [
              %{
                account: Map.fetch!(accounts, l.revenue_account_id),
                direction: "debit",
                amount: Dec.money(w)
              },
              %{
                account: Map.fetch!(accounts, l.inventory_account_id),
                direction: "credit",
                amount: Dec.money(w)
              }
            ]
          else
            []
          end
        end)

      sides = (receipt ++ dist ++ writeoff) |> Enum.filter(&(&1.amount != "0.00"))

      total =
        sides
        |> Enum.filter(&(&1.direction == "debit"))
        |> Enum.reduce(0, &(&2 + Dec.or0(&1.amount)))
        |> Dec.money()

      {:ok, sides, %{total: total}}
    end
  end

  defp accounts_by_id(company_id, lines, allocs) do
    ids =
      (Enum.flat_map(
         lines,
         &[&1.inventory_account_id, &1.revenue_account_id, &1.expense_account_id]
       ) ++
         Enum.map(allocs, & &1.account_id))
      |> Enum.uniq()
      |> Enum.filter(&(&1 > 0))

    found =
      Repo.all(from(a in Account, where: a.company_id == ^company_id and a.id in ^ids))
      |> Map.new(&{&1.id, &1})

    missing = Enum.find(ids, &(Map.get(found, &1) == nil))

    if missing do
      {:error, {422, "липсва сметка с id #{missing}"}}
    else
      {:ok, found}
    end
  end

  defp persist_lines(doc_id, lines, allocs) do
    alloc_by_product =
      Enum.reduce(allocs, %{}, fn a, acc ->
        Map.update(acc, a.product_id, a.amount, &(&1 + a.amount))
      end)

    Enum.each(lines, fn l ->
      q = l.quantity
      sold = l.sold_quantity
      full = l.amount + Map.get(alloc_by_product, l.product_id, 0)

      w =
        if q > 0 and sold > 0,
          do: round_to_money(Dec.mul(sold, Dec.div(full, q) || 0) || 0),
          else: 0

      alloc = Map.get(alloc_by_product, l.product_id, 0)

      Repo.update_all(
        from(x in ProductionReceiptLine,
          where: x.doc_id == ^doc_id and x.product_id == ^l.product_id
        ),
        set: [
          sold_quantity: Dec.qty(l.sold_quantity),
          sold_amount: Dec.money(l.sold_amount),
          ending_quantity: Dec.qty(l.ending_quantity),
          quantity: Dec.qty(l.quantity),
          unit_cost: Dec.text(l.unit_cost, 6),
          amount: Dec.money(l.amount),
          allocated_amount: Dec.money(alloc),
          writeoff_amount: Dec.money(w),
          coefficient: l.coefficient,
          manual_amount: l.manual_amount
        ]
      )
    end)
  end

  # Без натрупана стойност в 611 и без непреки разходи няма какво да се запише.
  defp values_present(lines) do
    if Enum.any?(lines, &(&1.amount > 0)) do
      :ok
    else
      {:error, {422, "няма натрупана стойност в 611 за месеца — записът на разходи липсва"}}
    end
  end

  defp insert_allocations(doc_id, allocs) do
    allocs
    |> Enum.with_index(1)
    |> Enum.each(fn {a, no} ->
      Repo.insert!(%ProductionReceiptAllocation{
        doc_id: doc_id,
        line_no: no,
        product_id: a.product_id,
        account_id: a.account_id,
        base_amount: Dec.money(a.base_amount),
        amount: Dec.money(a.amount)
      })
    end)
  end

  ## Вътрешни

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(ProductionReceipt, id: id, company_id: company_id) do
        nil -> {:error, {404, "документът не е намерен"}}
        doc -> {:ok, doc}
      end
    end
  end

  defp with_audit(company_id, doc) do
    one(doc, true)
    |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, @doc_type), doc.id))
    |> Map.put(:audit_history, Audit.history_for(company_id, @doc_type, doc.id))
  end

  defp one(doc, with_lines) do
    base = %{
      id: doc.id,
      number: doc.number,
      doc_date: doc.doc_date,
      month: doc.month,
      status: doc.status,
      notes: doc.notes,
      journal_entry_id: doc.journal_entry_id,
      wip_end_mode: doc.wip_end_mode,
      wip_end_value: doc.wip_end_value
    }

    if with_lines do
      base
      |> Map.put(:lines, lines_json(doc.id))
      |> Map.put(:allocations, allocations_json(doc.id))
    else
      base
    end
  end

  defp lines_of(doc_id) do
    Repo.all(
      from(l in ProductionReceiptLine,
        where: l.doc_id == ^doc_id,
        order_by: [asc: l.line_no, asc: l.id]
      )
    )
  end

  defp lines_json(doc_id) do
    lines_of(doc_id)
    |> Enum.map(fn l ->
      %{
        id: l.id,
        line_no: l.line_no,
        product_id: l.product_id,
        sold_quantity: l.sold_quantity,
        sold_amount: l.sold_amount,
        ending_quantity: l.ending_quantity,
        quantity: l.quantity,
        unit_cost: l.unit_cost,
        amount: l.amount,
        allocated_amount: l.allocated_amount,
        writeoff_amount: l.writeoff_amount,
        inventory_account_id: l.inventory_account_id,
        revenue_account_id: l.revenue_account_id,
        expense_account_id: l.expense_account_id,
        coefficient: l.coefficient,
        manual_amount: l.manual_amount
      }
    end)
  end

  defp allocations_json(doc_id) do
    Repo.all(
      from(a in ProductionReceiptAllocation,
        where: a.doc_id == ^doc_id,
        order_by: [asc: a.line_no, asc: a.id]
      )
    )
    |> Enum.map(fn a ->
      %{
        id: a.id,
        line_no: a.line_no,
        product_id: a.product_id,
        account_id: a.account_id,
        base_amount: a.base_amount,
        amount: a.amount
      }
    end)
  end

  defp doc_total(value) do
    value
    |> Map.get(:lines, [])
    |> Enum.reduce(0, fn l, sum -> sum + Dec.or0(l.amount) end)
    |> Dec.money()
  end

  defp no_other_confirmed(company_id, doc) do
    exists =
      Repo.exists?(
        from(d in ProductionReceipt,
          where:
            d.company_id == ^company_id and d.month == ^doc.month and d.status == "confirmed" and
              d.id != ^doc.id
        )
      )

    if exists do
      {:error, {409, "вече има потвърден приход на продукция за #{doc.month}"}}
    else
      :ok
    end
  end

  defp lines_ready(company_id, lines) do
    case Enum.reduce_while(lines, :ok, fn l, _acc ->
           cond do
             l.inventory_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 303"}}}

             l.revenue_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 701"}}}

             l.expense_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 611"}}}

             Dec.or0(l.quantity) < 0 ->
               {:halt, {:error, {422, "отрицателно произведено количество"}}}

             true ->
               {:cont, :ok}
           end
         end) do
      :ok -> account_refs_ok(company_id, lines)
      err -> err
    end
  end

  defp account_refs_ok(company_id, lines) do
    ids =
      Enum.flat_map(
        lines,
        &[&1.inventory_account_id, &1.revenue_account_id, &1.expense_account_id]
      )
      |> Enum.uniq()

    if Enum.all?(ids, &(Repo.get_by(Account, id: &1, company_id: company_id) != nil)) do
      :ok
    else
      {:error, {422, "липсва сметка от артикула"}}
    end
  end

  defp not_empty([]), do: {:error, {422, "документът няма редове"}}
  defp not_empty(_), do: :ok

  defp draft(%ProductionReceipt{status: "draft"}), do: :ok
  defp draft(_), do: {:error, {409, "потвърден документ не се променя"}}

  defp confirmed(%ProductionReceipt{status: "confirmed"}), do: :ok
  defp confirmed(_), do: {:error, {422, "документът не е потвърден"}}

  defp month_param(params) do
    case Params.str(params, "month") do
      {:present, m} ->
        m = String.trim(m)

        case String.split(m, "-") do
          [y, mo] ->
            with {_yi, ""} <- Integer.parse(y),
                 {mi, ""} <- Integer.parse(mo),
                 true <- mi in 1..12 do
              {:ok, m}
            else
              _ -> {:error, {422, "месецът е YYYY-MM"}}
            end

          _ ->
            {:error, {422, "месецът е YYYY-MM"}}
        end

      _ ->
        {:error, {422, "месецът е задължителен (YYYY-MM)"}}
    end
  end

  defp prefix(params, key, default) do
    case Params.str(params, key) do
      {:present, v} ->
        v = String.trim(v)
        if v == "", do: default, else: v

      _ ->
        default
    end
  end

  defp last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    days = Date.days_in_month(Date.new!(y, m, 1))
    "#{month}-#{String.pad_leading(Integer.to_string(days), 2, "0")}"
  end

  defp qty_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидно количество"}}
      value when value >= 0 -> {:ok, value}
      _ -> {:error, {422, "отрицателно количество"}}
    end
  end

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  defp string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

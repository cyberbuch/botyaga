defmodule Botyaga.Stock.MaterialIssues do
  @moduledoc """
  Ръчно изписване на материали към разходна сметка от правилата.
  Себестойността се смята при преизчислението, не се въвежда.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Journal, Params, Periods, Repo}
  alias Botyaga.Stock.{MaterialIssue, MaterialIssueLine, Replay, Rules}

  def index(company_id) do
    stamps = Audit.stamps_for(company_id, "material_issue")

    Repo.all(from(d in MaterialIssue, where: d.company_id == ^company_id, order_by: [asc: d.id]))
    |> Enum.map(fn d -> d |> one(false) |> Audit.attach_stamp(Map.get(stamps, d.id)) end)
  end

  def show(company_id, id) do
    with {:ok, doc} <- fetch(company_id, id) do
      {:ok, with_audit(company_id, doc)}
    end
  end

  def create(company_id, sub, params) do
    with {:ok, lines} <- parse_lines(company_id, params),
         :ok <- not_empty(lines),
         {:ok, loc} <- location(params, company_id) do
      date = string(params, "doc_date")
      notes = string(params, "notes")

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.insert!(%MaterialIssue{
              company_id: company_id,
              doc_date: date,
              location_id: loc,
              status: "draft",
              notes: notes,
              journal_entry_id: 0
            })

          doc = Repo.update!(Ecto.Changeset.change(doc, number: "МИ-#{doc.id}"))
          insert_lines(doc.id, lines)
          doc
        end)

      Audit.record(
        company_id,
        sub,
        "material_issue",
        doc.id,
        doc.number,
        "create",
        "Създаден документ за изписване на материали #{doc.number} (#{date})",
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
         {:ok, loc} <- pick_location(params, doc.location_id, company_id) do
      date = pick(params, "doc_date", doc.doc_date)
      notes = pick(params, "notes", doc.notes)
      before = one(doc, true)

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.update!(
              Ecto.Changeset.change(doc, doc_date: date, location_id: loc, notes: notes)
            )

          if Map.has_key?(params, "lines") do
            {:ok, lines} = parse_lines(company_id, params)
            Repo.delete_all(from(l in MaterialIssueLine, where: l.doc_id == ^doc.id))
            insert_lines(doc.id, lines)
          end

          doc
        end)

      after_value = one(doc, true)

      Audit.record(
        company_id,
        sub,
        "material_issue",
        doc.id,
        doc.number,
        "update",
        "Редактиран документ за изписване на материали #{doc.number} (#{date})",
        mat_total(before),
        mat_total(after_value),
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
      Repo.delete_all(from(l in MaterialIssueLine, where: l.doc_id == ^doc.id))
      Repo.delete!(doc)

      Audit.record(
        company_id,
        sub,
        "material_issue",
        doc.id,
        doc.number,
        "delete",
        "Изтрит документ за изписване на материали #{doc.number}",
        mat_total(before),
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  def confirm(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- draft(doc),
         :ok <- has_location(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date),
         lines = lines_of(doc.id),
         :ok <- not_empty(lines),
         :ok <- lines_allowed(company_id, lines) do
      {:ok, out} =
        Repo.transaction(fn ->
          Repo.update!(Ecto.Changeset.change(doc, status: "confirmed"))
          {:ok, out} = Replay.rebuild(company_id, "9999-12-31")
          out
        end)

      {:ok, after_doc} = fetch(company_id, id)
      after_value = one(after_doc, true)

      Audit.record(
        company_id,
        sub,
        "material_issue",
        id,
        after_doc.number,
        "post",
        "Потвърдено изписване на материали #{after_doc.number} (#{doc.doc_date}), сума #{mat_total(after_value)}",
        "0.00",
        mat_total(after_value),
        one(doc, true),
        after_value
      )

      {:ok, Map.put(with_audit(company_id, after_doc), :warnings, out.warnings)}
    end
  end

  def unpost(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- confirmed(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date) do
      before = one(doc, true)
      old_tot = mat_total(before)
      Journal.wipe(doc.journal_entry_id)

      Repo.update_all(from(l in MaterialIssueLine, where: l.doc_id == ^doc.id),
        set: [unit_cost: "0.000000", amount: "0.00"]
      )

      Repo.update!(Ecto.Changeset.change(doc, status: "draft", journal_entry_id: 0))

      {:ok, out} = Replay.rebuild(company_id, "9999-12-31")
      {:ok, after_doc} = fetch(company_id, id)

      Audit.record(
        company_id,
        sub,
        "material_issue",
        id,
        after_doc.number,
        "unpost",
        "Върнато в чернова изписване на материали #{after_doc.number}, стара сума #{old_tot}",
        old_tot,
        "0.00",
        before,
        one(after_doc, true)
      )

      {:ok, Map.put(with_audit(company_id, after_doc), :warnings, out.warnings)}
    end
  end

  ## Вътрешни

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(MaterialIssue, id: id, company_id: company_id) do
        nil -> {:error, {404, "документът не е намерен"}}
        doc -> {:ok, doc}
      end
    end
  end

  defp with_audit(company_id, doc) do
    one(doc, true)
    |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, "material_issue"), doc.id))
    |> Map.put(:audit_history, Audit.history_for(company_id, "material_issue", doc.id))
  end

  defp one(doc, with_lines) do
    base = %{
      id: doc.id,
      number: doc.number,
      doc_date: doc.doc_date,
      location_id: doc.location_id,
      status: doc.status,
      notes: doc.notes,
      journal_entry_id: doc.journal_entry_id
    }

    if with_lines, do: Map.put(base, :lines, lines_json(doc.id)), else: base
  end

  defp lines_of(doc_id) do
    Repo.all(
      from(l in MaterialIssueLine,
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
        product_id: l.product_id,
        quantity: l.quantity,
        unit_cost: l.unit_cost,
        amount: l.amount,
        account_id: l.account_id,
        inventory_account_id: l.inventory_account_id,
        line_no: l.line_no
      }
    end)
  end

  defp mat_total(value) do
    value
    |> Map.get(:lines, [])
    |> Enum.reduce(0, fn l, sum -> sum + Dec.or0(l.amount) end)
    |> Dec.money()
  end

  defp parse_lines(company_id, params) do
    case Map.get(params, "lines") do
      nil ->
        {:error, {422, "липсват редове"}}

      arr when is_list(arr) ->
        rules = Rules.load(company_id)
        parse_each(arr, company_id, rules, [])

      _ ->
        {:error, {422, "липсват редове"}}
    end
  end

  defp parse_each([], _company_id, _rules, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_each([line | rest], company_id, rules, acc) when is_map(line) do
    product_id = Params.integer(line, "product_id") || 0

    with {:ok, raw_quantity} <- required(line, "quantity"),
         {:ok, quantity} <- qty_of(raw_quantity),
         :ok <- positive(quantity, product_id),
         {:ok, account_id} <- ref(line, "account_id", Catalog.Account, company_id, "записът"),
         {:ok, inventory_account_id} <-
           ref(line, "inventory_account_id", Catalog.Account, company_id, "записът"),
         :ok <- product_exists(product_id, company_id),
         :ok <- allowed(company_id, rules, product_id, inventory_account_id, account_id) do
      parse_each(rest, company_id, rules, [
        %{
          product_id: product_id,
          quantity: quantity,
          account_id: account_id,
          inventory_account_id: inventory_account_id
        }
        | acc
      ])
    end
  end

  defp parse_each([_ | rest], company_id, rules, acc),
    do: parse_each(rest, company_id, rules, acc)

  defp allowed(company_id, rules, product_id, inventory, account) do
    if Rules.material_line_allowed(company_id, rules, product_id, inventory, account) do
      :ok
    else
      {:error, {422, "сметката не е в правилата за материали или в артикула"}}
    end
  end

  defp lines_allowed(company_id, lines) do
    rules = Rules.load(company_id)

    Enum.reduce_while(lines, :ok, fn line, _acc ->
      if Rules.material_line_allowed(
           company_id,
           rules,
           line.product_id,
           line.inventory_account_id,
           line.account_id
         ) do
        {:cont, :ok}
      else
        {:halt, {:error, {422, "редът не е по правило за материали или по сметката на артикула"}}}
      end
    end)
  end

  defp insert_lines(doc_id, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, no} ->
      Repo.insert!(%MaterialIssueLine{
        doc_id: doc_id,
        product_id: line.product_id,
        quantity: line.quantity,
        unit_cost: "0.000000",
        amount: "0.00",
        account_id: line.account_id,
        inventory_account_id: line.inventory_account_id,
        line_no: no
      })
    end)
  end

  defp qty_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидно количество"}}
      value -> {:ok, Dec.qty(value)}
    end
  end

  defp positive(quantity, product_id) do
    if Dec.or0(quantity) <= 0 or product_id <= 0,
      do: {:error, {422, "редът има артикул и положително количество"}},
      else: :ok
  end

  defp product_exists(id, company_id) do
    if Repo.get_by(Catalog.Product, id: id, company_id: company_id) == nil do
      {:error, {404, "артикулът не е намерен"}}
    else
      :ok
    end
  end

  defp ref(params, key, schema, company_id, what) do
    id = Params.integer(params, key) || 0

    if id > 0 and Repo.get_by(schema, id: id, company_id: company_id) == nil do
      {:error, {404, "#{what} не е намерен"}}
    else
      {:ok, id}
    end
  end

  defp location(params, company_id) do
    id = Params.integer(params, "location_id") || 0

    if id > 0 and Repo.get_by(Companies.Location, id: id, company_id: company_id) == nil do
      {:error, {404, "обектът не е намерен"}}
    else
      {:ok, id}
    end
  end

  defp pick_location(params, current, company_id) do
    case Params.integer(params, "location_id") do
      nil -> {:ok, current}
      {:error, _} -> {:ok, current}
      id -> location(%{"location_id" => id}, company_id)
    end
  end

  defp not_empty([]), do: {:error, {422, "документът няма редове"}}
  defp not_empty(_), do: :ok

  defp draft(%MaterialIssue{status: "draft"}), do: :ok
  defp draft(_), do: {:error, {409, "потвърден документ не се променя"}}

  defp confirmed(%MaterialIssue{status: "confirmed"}), do: :ok
  defp confirmed(_), do: {:error, {422, "документът не е потвърден"}}

  defp has_location(%MaterialIssue{location_id: loc}) when loc > 0, do: :ok
  defp has_location(_), do: {:error, {422, "нужен е складов обект"}}

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
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

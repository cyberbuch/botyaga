defmodule Botyaga.Stock.InternalDocs do
  @moduledoc "Вътрешни протоколи. Потвърждението мести артикули и ДМА между обекти."

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Params, Periods, Repo}
  alias Botyaga.Assets.{Asset, Event}
  alias Botyaga.Stock.{InternalDoc, InternalDocLine, Replay}

  def next_number(company_id) do
    max =
      Repo.all(from(d in InternalDoc, where: d.company_id == ^company_id, select: d.number))
      |> Enum.map(&to_int/1)
      |> Enum.max(fn -> 0 end)

    {:ok, %{number: (max + 1) |> Integer.to_string() |> String.pad_leading(10, "0")}}
  end

  def index(company_id) do
    stamps = Audit.stamps_for(company_id, "internal_doc")

    Repo.all(from(d in InternalDoc, where: d.company_id == ^company_id, order_by: [asc: d.id]))
    |> Enum.map(fn d -> d |> one() |> Audit.attach_stamp(Map.get(stamps, d.id)) end)
  end

  def show(company_id, id) do
    with {:ok, doc} <- fetch(company_id, id), do: {:ok, with_audit(company_id, doc)}
  end

  def create(company_id, sub, params) do
    with {:ok, lines} <- parse_lines(company_id, params),
         {:ok, number} <- number(params, company_id),
         {:ok, from_id} <- location(params, "from_location_id", company_id),
         {:ok, to_id} <- location(params, "to_location_id", company_id) do
      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.insert!(%InternalDoc{
              company_id: company_id,
              number: number,
              doc_date: string(params, "doc_date"),
              from_location_id: from_id,
              to_location_id: to_id,
              status: "draft",
              notes: string(params, "notes"),
              handed_by: string(params, "handed_by"),
              received_by: string(params, "received_by")
            })

          insert_lines(doc.id, lines)
          doc
        end)

      after_value = one(doc)

      Audit.record(
        company_id,
        sub,
        "internal_doc",
        doc.id,
        number,
        "create",
        "Създаден вътрешен протокол № #{number}, сума #{total(after_value)}",
        "",
        total(after_value),
        nil,
        after_value
      )

      show(company_id, doc.id)
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- not_confirmed(doc, "протоколът е вече потвърден"),
         {:ok, from_id} <-
           pick_location(params, "from_location_id", doc.from_location_id, company_id),
         {:ok, to_id} <- pick_location(params, "to_location_id", doc.to_location_id, company_id) do
      before = one(doc)
      number = pick(params, "number", doc.number)

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.update!(
              Ecto.Changeset.change(doc,
                number: number,
                doc_date: pick(params, "doc_date", doc.doc_date),
                from_location_id: from_id,
                to_location_id: to_id,
                notes: pick(params, "notes", doc.notes),
                handed_by: pick(params, "handed_by", doc.handed_by),
                received_by: pick(params, "received_by", doc.received_by)
              )
            )

          if Map.has_key?(params, "lines") do
            {:ok, lines} = parse_lines(company_id, params)
            Repo.delete_all(from(l in InternalDocLine, where: l.doc_id == ^doc.id))
            insert_lines(doc.id, lines)
          end

          doc
        end)

      after_value = one(doc)

      Audit.record(
        company_id,
        sub,
        "internal_doc",
        doc.id,
        number,
        "update",
        "Редактиран вътрешен протокол № #{number}, сума #{total(before)} → #{total(after_value)}",
        total(before),
        total(after_value),
        before,
        after_value
      )

      show(company_id, doc.id)
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- not_confirmed(doc, "потвърденият протокол не се трие") do
      before = one(doc)
      Repo.delete_all(from(l in InternalDocLine, where: l.doc_id == ^doc.id))
      Repo.delete!(doc)

      Audit.record(
        company_id,
        sub,
        "internal_doc",
        doc.id,
        doc.number,
        "delete",
        "Изтрит вътрешен протокол № #{doc.number}, сума #{total(before)}",
        total(before),
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  def confirm(company_id, sub, id) do
    with {:ok, doc} <- fetch(company_id, id),
         :ok <- not_confirmed(doc, "протоколът е вече потвърден"),
         :ok <- Periods.assert_open(company_id, doc.doc_date),
         :ok <- two_locations(doc),
         {:ok, from_name} <-
           place(company_id, doc.from_location_id, "обектът-източник не е намерен"),
         {:ok, to_name} <- place(company_id, doc.to_location_id, "обектът-приемник не е намерен"),
         lines = lines_of(doc.id) do
      Repo.transaction(fn ->
        {:ok, _moved} = apply_lines(company_id, doc, lines, from_name, to_name)
        Repo.update!(Ecto.Changeset.change(doc, status: "confirmed"))
        Replay.rebuild(company_id, "9999-12-31")
      end)

      {:ok, after_doc} = fetch(company_id, id)
      after_value = one(after_doc)

      Audit.record(
        company_id,
        sub,
        "internal_doc",
        after_doc.id,
        after_doc.number,
        "post",
        "Потвърден вътрешен протокол № #{after_doc.number} (#{from_name} → #{to_name})",
        total(after_value),
        total(after_value),
        one(doc),
        after_value
      )

      show(company_id, id)
    end
  end

  ## Вътрешни

  defp apply_lines(company_id, doc, lines, from_name, to_name) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, moved} ->
      case apply_line(company_id, doc, line, from_name, to_name) do
        {:ok, nil} ->
          {:cont, {:ok, moved}}

        {:ok, move} ->
          {:cont, {:ok, moved ++ [move]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp apply_line(company_id, doc, line, from_name, to_name) do
    if line.line_kind == "product" do
      with :ok <- product_exists(line.product_id, company_id),
           :ok <- positive(line.quantity) do
        {:ok, nil}
      end
    else
      case Repo.get_by(Asset, id: line.asset_id, company_id: company_id) do
        nil ->
          {:error, {422, "ДМА не е намерено: #{line.asset_id}"}}

        asset ->
          if asset.location_id != doc.from_location_id and asset.location_id != 0 do
            {:error, {422, "#{asset.name} не е в обекта-източник"}}
          else
            Repo.update!(Ecto.Changeset.change(asset, location_id: doc.to_location_id))
            reason = "протокол #{doc.number}: #{from_name} → #{to_name}"

            event =
              Repo.insert!(%Event{
                asset_id: asset.id,
                event_type: "movement",
                event_date: doc.doc_date,
                amount: "0.00",
                prev_value: "",
                location: to_name,
                reason: reason
              })

            {:ok, {asset.id, asset.location_id, event.id}}
          end
      end
    end
  end

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(InternalDoc, id: id, company_id: company_id) do
        nil -> {:error, {404, "Internal document not found"}}
        doc -> {:ok, doc}
      end
    end
  end

  defp with_audit(company_id, doc) do
    one(doc)
    |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, "internal_doc"), doc.id))
    |> Map.put(:audit_history, Audit.history_for(company_id, "internal_doc", doc.id))
  end

  defp one(doc) do
    %{
      id: doc.id,
      number: doc.number,
      doc_date: doc.doc_date,
      from_location_id: doc.from_location_id,
      to_location_id: doc.to_location_id,
      status: doc.status,
      notes: doc.notes,
      handed_by: doc.handed_by,
      received_by: doc.received_by,
      lines: lines_json(doc.id)
    }
  end

  defp lines_of(doc_id),
    do: Repo.all(from(l in InternalDocLine, where: l.doc_id == ^doc_id, order_by: [asc: l.id]))

  defp lines_json(doc_id) do
    lines_of(doc_id)
    |> Enum.map(fn l ->
      %{
        id: l.id,
        line_kind: l.line_kind,
        product_id: l.product_id,
        asset_id: l.asset_id,
        quantity: l.quantity,
        unit_cost: l.unit_cost,
        amount: l.amount,
        description: l.description
      }
    end)
  end

  defp total(value) do
    value
    |> Map.get(:lines, [])
    |> Enum.reduce(0, fn l, sum -> sum + Dec.or0(l.amount) end)
    |> Dec.money()
  end

  defp parse_lines(company_id, params) do
    case Map.get(params, "lines") do
      nil -> {:error, {422, "lines е задължителен масив"}}
      [] -> {:error, {422, "протоколът трябва да има поне един ред"}}
      arr when is_list(arr) -> parse_each(arr, company_id, [])
      _ -> {:error, {422, "lines е задължителен масив"}}
    end
  end

  defp parse_each([], _company_id, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_each([line | rest], company_id, acc) when is_map(line) do
    kind = string(line, "line_kind")

    cond do
      kind not in ["product", "fixed_asset"] ->
        {:error, {422, "line_kind трябва да е product или fixed_asset"}}

      kind == "product" and (Params.integer(line, "product_id") || 0) <= 0 ->
        {:error, {422, "артикулният ред изисква product_id"}}

      kind == "fixed_asset" and (Params.integer(line, "asset_id") || 0) <= 0 ->
        {:error, {422, "редът за ДМА изисква asset_id"}}

      true ->
        product_id = Params.integer(line, "product_id") || 0
        asset_id = Params.integer(line, "asset_id") || 0

        with :ok <- product_ref(product_id, company_id),
             {:ok, quantity} <- dec_of(string(line, "quantity", "0"), :qty),
             {:ok, unit_cost} <- dec_of(string(line, "unit_cost", "0"), :money),
             {:ok, amount} <- amount(line, quantity, unit_cost) do
          parse_each(rest, company_id, [
            %{
              kind: kind,
              product_id: product_id,
              asset_id: asset_id,
              quantity: quantity,
              unit_cost: unit_cost,
              amount: amount,
              description: string(line, "description")
            }
            | acc
          ])
        end
    end
  end

  defp parse_each(_, _company_id, _acc), do: {:error, {422, "lines е задължителен масив"}}

  defp amount(line, quantity, unit_cost) do
    case Params.str(line, "amount") do
      {:present, value} when value != "" -> dec_of(value, :money)
      _ -> {:ok, Dec.money(Dec.mul(Dec.or0(quantity), Dec.or0(unit_cost)))}
    end
  end

  defp dec_of(raw, kind) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна стойност"}}
      value -> {:ok, if(kind == :qty, do: Dec.qty(value), else: Dec.money(value))}
    end
  end

  defp insert_lines(doc_id, lines) do
    Enum.each(lines, fn line ->
      Repo.insert!(%InternalDocLine{
        doc_id: doc_id,
        line_kind: line.kind,
        product_id: line.product_id,
        asset_id: line.asset_id,
        quantity: line.quantity,
        unit_cost: line.unit_cost,
        amount: line.amount,
        description: line.description
      })
    end)
  end

  defp number(params, company_id) do
    case Params.str(params, "number") do
      {:present, value} ->
        if String.trim(value) == "" do
          {:ok, n} = next_number(company_id)
          {:ok, n.number}
        else
          {:ok, value}
        end

      _ ->
        {:ok, n} = next_number(company_id)
        {:ok, n.number}
    end
  end

  defp location(params, key, company_id) do
    id = Params.integer(params, key) || 0

    if id > 0 and Repo.get_by(Companies.Location, id: id, company_id: company_id) == nil do
      {:error, {404, "обектът не е намерен"}}
    else
      {:ok, id}
    end
  end

  defp pick_location(params, key, current, company_id) do
    case Params.integer(params, key) do
      nil -> {:ok, current}
      {:error, _} -> {:ok, current}
      id -> location(%{key => id}, key, company_id)
    end
  end

  defp product_ref(id, _company_id) when id <= 0, do: :ok

  defp product_ref(id, company_id) do
    if Repo.get_by(Catalog.Product, id: id, company_id: company_id) == nil do
      {:error, {404, "артикулът не е намерен"}}
    else
      :ok
    end
  end

  defp product_exists(id, company_id) do
    case Repo.get_by(Catalog.Product, id: id, company_id: company_id) do
      %{name: name} when name not in [nil, ""] -> :ok
      _ -> {:error, {422, "артикулът не е намерен"}}
    end
  end

  defp positive(quantity) do
    if Dec.or0(quantity) <= 0,
      do: {:error, {422, "количеството трябва да е положително"}},
      else: :ok
  end

  defp place(company_id, id, missing) do
    case Repo.get_by(Companies.Location, id: id, company_id: company_id) do
      nil -> {:error, {422, missing}}
      %{name: name} -> {:ok, if(name in [nil, ""], do: Integer.to_string(id), else: name)}
    end
  end

  defp two_locations(%InternalDoc{from_location_id: from, to_location_id: to})
       when from > 0 and to > 0 and from != to,
       do: :ok

  defp two_locations(_), do: {:error, {422, "нужни са два различни активни обекта"}}

  defp not_confirmed(%InternalDoc{status: "confirmed"}, message), do: {:error, {409, message}}
  defp not_confirmed(_, _), do: :ok

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end

  defp to_int(value) do
    case Integer.parse(String.trim(value || "")) do
      {n, _} -> n
      :error -> 0
    end
  end
end

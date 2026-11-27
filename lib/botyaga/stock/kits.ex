defmodule Botyaga.Stock.Kits do
  @moduledoc """
  Комплектоване на стоки (304) и продукция (303) — пакет по рецепта, без
  производствени разходи. Стойността на съставките се прехвърля към комплекта
  по тяхната себестойност (Дт комплект / Кт съставка). Както CONTROLISY.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Dec, Params, Periods, Repo}
  alias Botyaga.Stock.{Kit, KitLine, Replay}

  @doc_type "kit"

  def index(company_id) do
    Repo.all(from(k in Kit, where: k.company_id == ^company_id, order_by: [desc: k.id]))
    |> Enum.map(&one(&1, false))
  end

  def show(company_id, id) do
    with {:ok, k} <- fetch(company_id, id), do: {:ok, one(k, true)}
  end

  def create(company_id, sub, params) do
    with {:ok, date} <- required(params, "doc_date"),
         {:ok, output} <- product(company_id, Params.integer(params, "output_product_id") || 0),
         :ok <- output_kind(output, kind(params)),
         {:ok, lines} <- parse_lines(company_id, params, kind(params)) do
      {:ok, k} =
        Repo.transaction(fn ->
          k =
            Repo.insert!(%Kit{
              company_id: company_id,
              doc_date: date,
              status: "draft",
              kind: kind(params),
              output_product_id: output.id,
              quantity: pick(params, "quantity", "1"),
              location_id: Params.integer(params, "location_id") || 0,
              recipe_id: Params.integer(params, "recipe_id") || 0,
              notes: pick(params, "notes", "")
            })

          k = Repo.update!(Ecto.Changeset.change(k, number: "КП-#{k.id}"))
          insert_lines(k.id, lines)
          k
        end)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        k.id,
        k.number,
        "create",
        "Създадено комплектоване #{k.number}",
        "",
        "0.00",
        nil,
        one(k, true)
      )

      show(company_id, k.id)
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, k} <- fetch_draft(company_id, id),
         {:ok, lines} <- parse_lines(company_id, params, k.kind) do
      {:ok, k} =
        Repo.transaction(fn ->
          k =
            Repo.update!(
              Ecto.Changeset.change(k,
                doc_date: pick(params, "doc_date", k.doc_date),
                quantity: pick(params, "quantity", k.quantity),
                location_id: pick_int(params, "location_id", k.location_id),
                notes: pick(params, "notes", k.notes)
              )
            )

          if Map.has_key?(params, "lines") do
            Repo.delete_all(from(l in KitLine, where: l.kit_id == ^k.id))
            insert_lines(k.id, lines)
          end

          k
        end)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        k.id,
        k.number,
        "update",
        "Редактирано комплектоване #{k.number}",
        "",
        "0.00",
        nil,
        one(k, true)
      )

      show(company_id, k.id)
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, k} <- fetch_draft(company_id, id) do
      Repo.delete!(k)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        k.id,
        k.number,
        "delete",
        "Изтрито комплектоване #{k.number}",
        "",
        "0.00",
        nil,
        nil
      )

      {:ok, nil}
    end
  end

  def confirm(company_id, sub, id) do
    with {:ok, k} <- fetch_draft(company_id, id),
         :ok <- Periods.assert_open(company_id, k.doc_date),
         :ok <- has_location(k),
         lines = lines_of(k.id),
         :ok <- not_empty(lines) do
      Repo.transaction(fn ->
        Repo.update!(
          Ecto.Changeset.change(k, status: "completed", cost: "0.00", journal_entry_id: 0)
        )

        Replay.rebuild(company_id, "9999-12-31")
      end)

      {:ok, after_k} = fetch(company_id, id)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        after_k.number,
        "post",
        "Потвърдено комплектоване #{after_k.number}, себестойност #{after_k.cost}",
        "0.00",
        after_k.cost,
        nil,
        one(after_k, true)
      )

      show(company_id, id)
    end
  end

  def unpost(company_id, sub, id) do
    with {:ok, k} <- fetch_completed(company_id, id),
         :ok <- Periods.assert_open(company_id, k.doc_date) do
      Repo.transaction(fn ->
        Repo.update!(Ecto.Changeset.change(k, status: "draft", cost: "0.00", journal_entry_id: 0))
        Replay.rebuild(company_id, "9999-12-31")
      end)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        k.number,
        "unpost",
        "Върнато в чернова комплектоване #{k.number}",
        k.cost,
        "0.00",
        nil,
        nil
      )

      show(company_id, id)
    end
  end

  ## Вътрешни

  defp kind(params), do: pick(params, "kind", "kit_goods")

  defp output_kind(output, kind) do
    want = if kind == "kit_production", do: "303", else: "304"
    acct = Repo.get(Catalog.Account, output.inventory_account_id)

    cond do
      acct == nil -> {:error, {422, "комплектът няма инвентарна сметка"}}
      String.starts_with?(acct.number, want) -> :ok
      true -> {:error, {422, "за #{kind} комплектът трябва да е по #{want}"}}
    end
  end

  defp parse_lines(company_id, params, kind) do
    arr = Map.get(params, "lines") || []

    Enum.reduce_while(arr, {:ok, []}, fn l, {:ok, acc} ->
      pid = Params.integer(l, "product_id") || 0

      with {:ok, p} <- product(company_id, pid),
           {:ok, q} <- qty(l),
           :ok <- component_kind(p, kind) do
        {:cont, {:ok, acc ++ [%{product_id: pid, quantity: q}]}}
      else
        err -> {:halt, err}
      end
    end)
  end

  # В комплект от стоки не може собствен продукт (приходът му е 701, не 702).
  defp component_kind(p, "kit_goods") do
    acct = Repo.get(Catalog.Account, p.inventory_account_id)
    rev = Repo.get(Catalog.Account, p.revenue_account_id)

    cond do
      acct && String.starts_with?(acct.number, "303") ->
        {:error,
         {422,
          "собствен продукт не може в комплект от стоки — ползвайте комплектоване на продукция"}}

      rev && String.starts_with?(rev.number, "701") ->
        {:error, {422, "собствен продукт не може в комплект от стоки"}}

      true ->
        :ok
    end
  end

  defp component_kind(_p, _kind), do: :ok

  defp product(company_id, id) do
    case Repo.get_by(Catalog.Product, id: id, company_id: company_id) do
      nil -> {:error, {404, "артикулът не е намерен"}}
      p -> {:ok, p}
    end
  end

  defp qty(l) do
    case Dec.parse(Map.get(l, "quantity")) do
      nil ->
        {:error, {422, "невалидно количество"}}

      q ->
        if q > 0,
          do: {:ok, Dec.qty(q)},
          else: {:error, {422, "количеството трябва да е положително"}}
    end
  end

  defp insert_lines(kit_id, lines) do
    Enum.each(lines, fn l ->
      %KitLine{}
      |> Ecto.Changeset.change(%{kit_id: kit_id, product_id: l.product_id, quantity: l.quantity})
      |> Repo.insert!()
    end)
  end

  defp lines_of(kit_id),
    do: Repo.all(from(l in KitLine, where: l.kit_id == ^kit_id, order_by: [asc: l.id]))

  defp fetch(company_id, id), do: Repo.get_by(Kit, id: id, company_id: company_id) |> ok404()

  defp fetch_draft(company_id, id) do
    with {:ok, k} <- fetch(company_id, id) do
      if k.status == "draft",
        do: {:ok, k},
        else: {:error, {422, "потвърдено комплектоване не се променя"}}
    end
  end

  defp fetch_completed(company_id, id) do
    with {:ok, k} <- fetch(company_id, id) do
      if k.status == "completed", do: {:ok, k}, else: {:error, {422, "не е потвърдено"}}
    end
  end

  defp ok404(nil), do: {:error, {404, "комплектоването не е намерено"}}
  defp ok404(k), do: {:ok, k}

  defp has_location(%Kit{location_id: loc}) when loc > 0, do: :ok
  defp has_location(_), do: {:error, {422, "нужен е складов обект"}}

  defp not_empty([]), do: {:error, {422, "няма съставки"}}
  defp not_empty(_), do: :ok

  defp one(k, with_lines) do
    base = %{
      id: k.id,
      number: k.number,
      doc_date: k.doc_date,
      status: k.status,
      kind: k.kind,
      output_product_id: k.output_product_id,
      quantity: k.quantity,
      location_id: k.location_id,
      recipe_id: k.recipe_id,
      cost: k.cost,
      journal_entry_id: k.journal_entry_id,
      notes: k.notes
    }

    if with_lines do
      Map.put(
        base,
        :lines,
        Enum.map(lines_of(k.id), fn l ->
          %{id: l.id, product_id: l.product_id, quantity: l.quantity}
        end)
      )
    else
      base
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, v} when v != "" -> {:ok, v}
      _ -> {:error, {422, "#{key} е задължително"}}
    end
  end

  defp pick(params, key, default) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> default
    end
  end

  defp pick_int(params, key, default) do
    case Params.integer(params, key) do
      nil -> default
      v -> v
    end
  end
end

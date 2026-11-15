defmodule Botyaga.Pnmap do
  @moduledoc """
  Име от сканиран документ към наш артикул. Търсенето по име е в приложението.
  Порт на `pnmap.rs`: CRUD + съпоставяне на контрагент/артикул за UBL и OCR.
  """

  import Ecto.Query

  alias Botyaga.{Companies, Params, Repo}
  alias Botyaga.Catalog.{Counterpart, Product}
  alias Botyaga.Invoicing.Invoice
  alias Botyaga.Pnmap.Mapping
  alias BotyagaWeb.Render

  def norm(raw) do
    (raw || "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.downcase()
  end

  def index(company_id, params) do
    id = Params.integer(params, "counterpart_id") || 0

    with :ok <- maybe_counterpart(company_id, id) do
      items = company_id |> rows_of(id) |> Enum.map(&row_json/1)
      {:ok, Render.page(items, params)}
    end
  end

  def save(company_id, params) do
    counterpart = Params.integer(params, "counterpart_id") || 0

    cond do
      counterpart <= 0 ->
        {:error, {422, "counterpart_id е задължителен"}}

      Repo.get_by(Counterpart, id: counterpart, company_id: company_id) == nil ->
        {:error, {404, "контрагентът не е намерен"}}

      true ->
        items = Map.get(params, "items") || []
        existing = rows_of(company_id, counterpart)
        by_name = Map.new(existing, &{&1.scanned_name, &1.id})

        case Enum.reduce_while(items, {:ok, by_name}, fn item, {:ok, acc} ->
               case upsert(company_id, counterpart, item, acc) do
                 {:ok, acc2} -> {:cont, {:ok, acc2}}
                 {:error, _} = error -> {:halt, error}
               end
             end) do
          {:ok, _} ->
            result = company_id |> rows_of(counterpart) |> Enum.map(&row_json/1)
            {:ok, Render.page(result, %{})}

          {:error, _} = error ->
            error
        end
    end
  end

  defp upsert(company_id, counterpart, item, by_name) when is_map(item) do
    name = norm(str(item, "scanned_name"))
    product = Params.integer(item, "product_id") || 0

    cond do
      name == "" or product <= 0 ->
        {:ok, by_name}

      Repo.get_by(Product, id: product, company_id: company_id) == nil ->
        {:error, {404, "артикулът не е намерен"}}

      true ->
        case Map.fetch(by_name, name) do
          {:ok, id} ->
            Repo.update_all(
              from(m in Mapping, where: m.id == ^id and m.company_id == ^company_id),
              set: [product_id: product]
            )

            {:ok, by_name}

          :error ->
            mapping =
              Repo.insert!(%Mapping{
                company_id: company_id,
                counterpart_id: counterpart,
                scanned_name: name,
                product_id: product
              })

            {:ok, Map.put(by_name, name, mapping.id)}
        end
    end
  end

  defp upsert(_company_id, _counterpart, _item, by_name), do: {:ok, by_name}

  def counterpart_hit(company_id, vat, eik) do
    Repo.all(from(c in Counterpart, where: c.company_id == ^company_id, order_by: [asc: c.id]))
    |> Enum.find_value(fn c ->
      have_eik = c.eik || ""
      have_vat = c.vat_number || ""
      vat_ok = same_id(have_vat, vat)

      eik_ok =
        same_eik(have_eik, eik) or same_eik(have_eik, digits(vat)) or
          same_eik(eik, digits(have_vat))

      if vat_ok or eik_ok, do: %{id: c.id, name: c.name || "", eik: have_eik, vat: have_vat}
    end)
  end

  def product_by_code(company_id, code) do
    want = code |> String.trim() |> String.downcase()

    if want == "" do
      0
    else
      Repo.all(from(p in Product, where: p.company_id == ^company_id, order_by: [asc: p.id]))
      |> Enum.find_value(0, fn p ->
        if String.downcase(String.trim(p.code || "")) == want, do: p.id
      end)
    end
  end

  def invoice_by_number(company_id, number) do
    want = String.trim(number || "")

    if want == "" do
      0
    else
      Repo.all(from(i in Invoice, where: i.company_id == ^company_id, order_by: [asc: i.id]))
      |> Enum.find_value(0, fn i -> if String.trim(i.number || "") == want, do: i.id end)
    end
  end

  def product_for(company_id, counterpart_id, name, seller) do
    if counterpart_id <= 0 do
      0
    else
      rows =
        Repo.all(
          from(m in Mapping,
            where: m.company_id == ^company_id and m.counterpart_id == ^counterpart_id,
            order_by: [asc: m.id]
          )
        )

      want = norm(name)
      seller_n = norm(seller)

      by_name =
        if want == "",
          do: nil,
          else: Enum.find_value(rows, fn m -> if m.scanned_name == want, do: m.product_id end)

      by_seller =
        if seller_n == "",
          do: nil,
          else: Enum.find_value(rows, fn m -> if m.scanned_name == seller_n, do: m.product_id end)

      by_name || by_seller || 0
    end
  end

  def company_vat_registered(company_id) do
    case Companies.get_company(company_id) do
      nil -> false
      c -> c.is_vat_registered == 1 and String.trim(c.vat_number || "") != ""
    end
  end

  defp rows_of(company_id, 0),
    do: Repo.all(from(m in Mapping, where: m.company_id == ^company_id, order_by: [asc: m.id]))

  defp rows_of(company_id, id),
    do:
      Repo.all(
        from(m in Mapping,
          where: m.company_id == ^company_id and m.counterpart_id == ^id,
          order_by: [asc: m.id]
        )
      )

  defp row_json(m) do
    %{
      id: m.id,
      counterpart_id: m.counterpart_id,
      scanned_name: m.scanned_name,
      product_id: m.product_id
    }
  end

  defp maybe_counterpart(_company_id, id) when id <= 0, do: :ok

  defp maybe_counterpart(company_id, id) do
    if Repo.get_by(Counterpart, id: id, company_id: company_id),
      do: :ok,
      else: {:error, {404, "контрагентът не е намерен"}}
  end

  defp same_id(a, b) do
    x = a |> String.trim() |> String.downcase()
    y = b |> String.trim() |> String.downcase()
    x != "" and x == y
  end

  defp same_eik(a, b),
    do: not placeholder_eik?(a) and not placeholder_eik?(b) and same_id(a, b)

  defp placeholder_eik?(eik) do
    text = String.trim(eik || "")
    text == "" or String.starts_with?(text, "999")
  end

  defp digits(raw), do: String.replace(raw || "", ~r/[^0-9]/, "")

  defp str(map, key) do
    case Map.get(map, key) do
      nil -> ""
      v -> to_string(v)
    end
  end
end

defmodule Botyaga.Vies do
  @moduledoc "Справка във VIES (REST API) и нов контрагент от нея. Порт на `vies.rs`."

  alias Botyaga.{Addr, Params, Pnmap, Repo}
  alias Botyaga.Catalog.Counterpart
  alias BotyagaWeb.Render

  @eu ~w(AT BE BG CY CZ DE DK EE ES FI FR EL HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK XI GR)

  def lookup(company_id, params) do
    vat = normalize(str(params, "vat"))

    if not shape_ok(vat) do
      {:error, {422, "vat трябва да е ЕС ДДС номер (напр. BG123456789)"}}
    else
      with {:ok, hit} <- fetch(vat) do
        raw = if hit.address == "---", do: "", else: hit.address
        cc = String.slice(vat, 0, 2)

        with {:ok, {parts, note}} <- Addr.split(company_id, raw, cc, "", "") do
          {:ok, lookup_json(vat, hit, parts, note)}
        end
      end
    end
  end

  def create(company_id, params) do
    with {:ok, raw_vat} <- required(params, "vat_number") do
      vat = normalize(raw_vat)

      cond do
        not shape_ok(vat) ->
          {:error, {422, "vat_number трябва да е ЕС ДДС номер (напр. BG123456789)"}}

        true ->
          kind = params |> str("counterpart_type") |> or_default("both") |> String.trim()

          if kind not in ["customer", "supplier", "both"] do
            {:error, {422, "counterpart_type трябва да е customer/supplier/both"}}
          else
            create_validated(company_id, vat, kind)
          end
      end
    end
  end

  defp create_validated(company_id, vat, kind) do
    with {:ok, hit} <- fetch(vat) do
      if not hit.valid do
        {:error, {422, "ДДС номерът не е намерен във VIES"}}
      else
        cc = String.slice(vat, 0, 2)
        eik = if cc == "BG", do: String.slice(vat, 2..-1//1), else: "999999999"

        case Pnmap.counterpart_hit(company_id, vat, eik) do
          %{id: id} ->
            case Repo.get_by(Counterpart, id: id, company_id: company_id) do
              nil -> create_new(company_id, vat, kind, hit, cc, eik)
              existing -> {:ok, Render.counterpart(existing), 200}
            end

          nil ->
            create_new(company_id, vat, kind, hit, cc, eik)
        end
      end
    end
  end

  defp create_new(company_id, vat, kind, hit, cc, eik) do
    addr_raw = if hit.address == "---", do: "", else: hit.address

    with {:ok, {parts, _}} <- Addr.split(company_id, addr_raw, cc, "", "") do
      name = if hit.name == "" or hit.name == "---", do: "VIES #{vat}", else: hit.name
      country = if parts.country == "", do: cc, else: parts.country

      map = %{
        "name" => name,
        "counterpart_type" => kind,
        "eik" => eik,
        "vat_number" => vat,
        "address" => addr_raw,
        "vies_address" => addr_raw,
        "city" => parts.city,
        "post_code" => parts.post_code,
        "country" => country,
        "street_name" => parts.street_name,
        "building_number" => parts.building_number,
        "address_building" => parts.address_building,
        "additional_address_detail" => parts.additional_address_detail,
        "address_type" => parts.address_type,
        "region" => parts.region
      }

      with {:ok, counterpart} <- Botyaga.Catalog.Counterparts.create(company_id, map) do
        {:ok, Render.counterpart(counterpart), 201}
      end
    end
  end

  defp fetch(vat) do
    cc = api_cc(String.slice(vat, 0, 2))
    num = String.slice(vat, 2..-1//1)
    url = "https://ec.europa.eu/taxation_customs/vies/rest-api/ms/#{cc}/vat/#{num}"

    case Req.get(url, receive_timeout: 20_000, retry: false) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok,
         %{
           valid: Map.get(body, "isValid") == true,
           name: text(body, "name"),
           address: text(body, "address"),
           user_error: text(body, "userError"),
           request_date: text(body, "requestDate")
         }}

      {:ok, %{status: 200}} ->
        {:error, {502, "невалиден JSON отговор от VIES"}}

      {:ok, %{status: status}} ->
        {:error, {502, "VIES върна статус #{status} — опитайте пак"}}

      {:error, _} ->
        {:error, {502, "VIES услугата е недостъпна (мрежова грешка)"}}
    end
  end

  defp text(body, key), do: body |> Map.get(key, "") |> to_string() |> String.trim()

  defp lookup_json(vat, hit, parts, note) do
    parts
    |> Addr.parts_json(note)
    |> Map.merge(%{
      valid: hit.valid,
      name: hit.name,
      address: hit.address,
      vies_address: hit.address,
      user_error: hit.user_error,
      request_date: hit.request_date,
      vat_number: vat,
      country_code: String.slice(vat, 0, 2)
    })
  end

  def normalize(raw) do
    (raw || "")
    |> String.graphemes()
    |> Enum.filter(&String.match?(&1, ~r/^[A-Za-z0-9]$/))
    |> Enum.join()
    |> String.upcase()
  end

  def shape_ok(vat) do
    String.length(vat) in 4..15 and String.slice(vat, 0, 2) in @eu
  end

  defp api_cc("GR"), do: "EL"
  defp api_cc(cc), do: cc

  defp or_default(value, fallback), do: if(String.trim(value) == "", do: fallback, else: value)

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

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

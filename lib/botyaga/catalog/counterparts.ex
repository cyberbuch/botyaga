defmodule Botyaga.Catalog.Counterparts do
  @moduledoc """
  Контрагенти на фирма. Адресните полета са в същия ред (Octo ги държеше в
  `counterpart_extra`). Дубликат по ЕИК/ДДС не се допуска; `999…` е за
  еднократни и чужди контрагенти.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Catalog.Counterpart

  @types ~w(customer supplier both)
  @type_message "counterpart_type е customer, supplier или both"
  @address_types ~w(StreetAddress PostalAddress BillingAddress ShipToAddress ShipFromAddress)
  @address_message "address_type е StreetAddress, PostalAddress, BillingAddress, ShipToAddress или ShipFromAddress"

  @string_fields ~w(eik vat_number address city post_code country contact_person vies_address
                     street_name building_number address_building additional_address_detail email phone)

  def list(company_id) do
    Repo.all(from(c in Counterpart, where: c.company_id == ^company_id, order_by: [asc: c.id]))
  end

  def get(company_id, id) do
    case Repo.get_by(Counterpart, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "контрагентът не е намерен"}}
      counterpart -> {:ok, counterpart}
    end
  end

  def create(company_id, params) do
    with {:ok, counterpart} <- apply_params(%Counterpart{company_id: company_id}, params, true),
         :ok <- check_duplicate(company_id, counterpart.eik, counterpart.vat_number, 0) do
      {:ok, Repo.insert!(counterpart)}
    end
  end

  def update(company_id, id, params) do
    with {:ok, current} <- get(company_id, id),
         {:ok, counterpart} <- apply_params(current, params, false),
         :ok <-
           check_duplicate(company_id, counterpart.eik, counterpart.vat_number, Params.id(id)) do
      {:ok, Repo.update!(Ecto.Changeset.change(current, Map.take(counterpart, fields())))}
    end
  end

  def delete(company_id, id) do
    with {:ok, counterpart} <- get(company_id, id) do
      Repo.delete!(counterpart)
      {:ok, nil}
    end
  end

  defp fields do
    [
      :name,
      :counterpart_type,
      :eik,
      :vat_number,
      :address,
      :city,
      :post_code,
      :country,
      :contact_person,
      :vies_address,
      :street_name,
      :building_number,
      :address_building,
      :additional_address_detail,
      :address_type,
      :region,
      :email,
      :phone
    ]
  end

  defp apply_params(counterpart, params, fresh?) do
    with {:ok, name} <- name(counterpart, params, fresh?),
         {:ok, type} <- counterpart_type(counterpart, params),
         {:ok, address_type} <- address_type(counterpart, params, fresh?),
         {:ok, region} <- region(counterpart, params, fresh?) do
      changes =
        Enum.reduce(
          @string_fields,
          %{name: name, counterpart_type: type, address_type: address_type, region: region},
          fn field, acc ->
            case Params.str(params, field) do
              {:present, value} -> Map.put(acc, String.to_existing_atom(field), value)
              _ -> acc
            end
          end
        )

      counterpart = Ecto.Changeset.change(counterpart, changes) |> Ecto.Changeset.apply_changes()
      {:ok, normalize(counterpart)}
    end
  end

  defp name(counterpart, params, fresh?) do
    case Params.str(params, "name") do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "name е задължително"}},
          else: {:ok, value}

      {:error, _} ->
        {:error, {422, "name трябва да е низ"}}

      :absent ->
        if fresh?, do: {:error, {422, "name е задължително"}}, else: {:ok, counterpart.name}
    end
  end

  defp counterpart_type(counterpart, params) do
    case Params.str(params, "counterpart_type") do
      :absent ->
        {:ok, counterpart.counterpart_type}

      {:present, value} ->
        value = String.trim(value)
        if value in @types, do: {:ok, value}, else: {:error, {422, @type_message}}

      {:error, _} ->
        {:error, {422, @type_message}}
    end
  end

  defp address_type(counterpart, params, fresh?) do
    if Map.has_key?(params, "address_type") or fresh? do
      raw = string(params, "address_type", counterpart.address_type)
      text = String.trim(raw)

      cond do
        text == "" ->
          {:ok, ""}

        canon = Enum.find(@address_types, &(String.upcase(&1) == String.upcase(text))) ->
          {:ok, canon}

        true ->
          {:error, {422, @address_message}}
      end
    else
      {:ok, counterpart.address_type}
    end
  end

  defp region(counterpart, params, fresh?) do
    if Map.has_key?(params, "region") or fresh? do
      raw = string(params, "region", counterpart.region)

      country =
        if String.trim(counterpart.country || "") == "",
          do: "BG",
          else: String.trim(counterpart.country)

      case Catalog.region_code(raw, country) do
        {:ok, code} -> {:ok, code}
        {:error, :invalid} -> {:error, {422, "region трябва да е код BG-01 … BG-28"}}
      end
    else
      {:ok, counterpart.region}
    end
  end

  defp normalize(counterpart) do
    country =
      case String.trim(counterpart.country || "") do
        "" -> "BG"
        value -> String.upcase(value)
      end

    vat = counterpart.vat_number |> to_string() |> String.trim() |> String.upcase()
    eik = counterpart.eik |> to_string() |> String.trim()

    eik =
      if eik == "" do
        cond do
          String.starts_with?(vat, "BG") ->
            digits = vat |> String.slice(2..-1//1) |> String.replace(~r/[^0-9]/, "")
            if digits == "", do: eik, else: digits

          String.upcase(country) != "BG" or (vat != "" and not String.starts_with?(vat, "BG")) ->
            "999999999"

          true ->
            eik
        end
      else
        eik
      end

    type =
      if String.trim(counterpart.counterpart_type || "") == "",
        do: "both",
        else: counterpart.counterpart_type

    %{counterpart | country: country, vat_number: vat, eik: eik, counterpart_type: type}
  end

  defp check_duplicate(company_id, eik, vat, exclude_id) do
    vat = String.trim(vat || "")
    eik = String.trim(eik || "")

    if vat == "" and placeholder_eik?(eik) do
      :ok
    else
      others =
        Repo.all(
          from(c in Counterpart,
            where: c.company_id == ^company_id and c.id != ^exclude_id,
            select: {c.eik, c.vat_number}
          )
        )

      cond do
        Enum.any?(others, fn {_eik, have_vat} ->
          have_vat = String.trim(have_vat || "")
          vat != "" and have_vat != "" and String.downcase(vat) == String.downcase(have_vat)
        end) ->
          {:error, {409, "контрагент с този ДДС номер вече съществува"}}

        Enum.any?(others, fn {have_eik, _vat} ->
          have_eik = String.trim(have_eik || "")

          not placeholder_eik?(eik) and not placeholder_eik?(have_eik) and
              String.downcase(eik) == String.downcase(have_eik)
        end) ->
          {:error, {409, "контрагент с този ЕИК вече съществува"}}

        true ->
          :ok
      end
    end
  end

  defp placeholder_eik?(eik) do
    text = String.trim(eik || "")
    text == "" or String.starts_with?(text, "999")
  end

  defp string(params, key, default) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default || ""
    end
  end
end

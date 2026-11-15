defmodule Botyaga.Companies.Related do
  @moduledoc """
  Обекти, действителни собственици, крайни майки и серии на фирмата.
  Всеки запис се проверява спрямо активната фирма — чужд е 404.
  """

  import Ecto.Query

  alias Botyaga.Repo
  alias Botyaga.Params
  alias Botyaga.Companies.{Location, Owner, Parent, Series}

  @location_types ~w(OFFICE STORE WAREHOUSE BRANCH OTHER)
  @location_message "location_type трябва да е OFFICE, STORE, WAREHOUSE, BRANCH или OTHER"

  ## Обекти

  def create_location(company_id, params) do
    with {:ok, name} <- required(params, "name", "name е задължително"),
         {:ok, type} <- location_type(params),
         {:ok, country} <- country(params) do
      location = %Location{
        company_id: company_id,
        name: String.trim(name),
        location_type: type,
        street_name: string(params, "street_name"),
        building_number: string(params, "building_number"),
        city: String.trim(string(params, "city")),
        post_code: String.trim(string(params, "post_code")),
        region: String.trim(string(params, "region")),
        country: country,
        is_main: flag(params, "is_main")
      }

      {:ok, Repo.insert!(location)}
    end
  end

  def update_location(company_id, id, params) do
    with {:ok, location} <- load(company_id, Location, id, "обектът не е намерен"),
         {:ok, name} <- required(params, "name", "name е задължително", location.name),
         {:ok, type} <- location_type(params, location.location_type),
         {:ok, country} <- country(params, location.country) do
      location =
        Ecto.Changeset.change(location,
          name: String.trim(name),
          location_type: type,
          street_name: string(params, "street_name", location.street_name),
          building_number: string(params, "building_number", location.building_number),
          city: String.trim(string(params, "city", location.city)),
          post_code: String.trim(string(params, "post_code", location.post_code)),
          region: String.trim(string(params, "region", location.region)),
          country: country,
          is_main: flag(params, "is_main", location.is_main)
        )

      {:ok, Repo.update!(location)}
    end
  end

  def delete_location(company_id, id) do
    with {:ok, location} <- load(company_id, Location, id, "обектът не е намерен") do
      Repo.delete!(location)
      {:ok, nil}
    end
  end

  ## Действителни собственици

  def create_owner(company_id, params) do
    with {:ok, first} <- required(params, "first_name_bg", "first_name_bg е задължително"),
         {:ok, last} <- required(params, "last_name_bg", "last_name_bg е задължително"),
         {:ok, country} <- country(params) do
      owner = %Owner{
        company_id: company_id,
        first_name_bg: String.trim(first),
        last_name_bg: String.trim(last),
        egn: String.trim(string(params, "egn")),
        first_name_latin: String.trim(string(params, "first_name_latin")),
        last_name_latin: String.trim(string(params, "last_name_latin")),
        country: country,
        ownership_percentage: String.trim(string(params, "ownership_percentage"))
      }

      {:ok, Repo.insert!(owner)}
    end
  end

  def update_owner(company_id, id, params) do
    with {:ok, owner} <- load(company_id, Owner, id, "собственикът не е намерен"),
         {:ok, first} <-
           required(params, "first_name_bg", "first_name_bg е задължително", owner.first_name_bg),
         {:ok, last} <-
           required(params, "last_name_bg", "last_name_bg е задължително", owner.last_name_bg),
         {:ok, country} <- country(params, owner.country) do
      owner =
        Ecto.Changeset.change(owner,
          first_name_bg: String.trim(first),
          last_name_bg: String.trim(last),
          egn: String.trim(string(params, "egn", owner.egn)),
          first_name_latin:
            String.trim(string(params, "first_name_latin", owner.first_name_latin)),
          last_name_latin: String.trim(string(params, "last_name_latin", owner.last_name_latin)),
          country: country,
          ownership_percentage:
            String.trim(string(params, "ownership_percentage", owner.ownership_percentage))
        )

      {:ok, Repo.update!(owner)}
    end
  end

  def delete_owner(company_id, id) do
    with {:ok, owner} <- load(company_id, Owner, id, "собственикът не е намерен") do
      Repo.delete!(owner)
      {:ok, nil}
    end
  end

  ## Крайни майки

  def create_parent(company_id, params) do
    with {:ok, name} <- required(params, "name_bg", "name_bg е задължително"),
         {:ok, country} <- country(params) do
      parent = %Parent{
        company_id: company_id,
        name_bg: String.trim(name),
        uic: String.trim(string(params, "uic")),
        name_latin: String.trim(string(params, "name_latin")),
        country: country
      }

      {:ok, Repo.insert!(parent)}
    end
  end

  def update_parent(company_id, id, params) do
    with {:ok, parent} <- load(company_id, Parent, id, "предприятието майка не е намерено"),
         {:ok, name} <- required(params, "name_bg", "name_bg е задължително", parent.name_bg),
         {:ok, country} <- country(params, parent.country) do
      parent =
        Ecto.Changeset.change(parent,
          name_bg: String.trim(name),
          uic: String.trim(string(params, "uic", parent.uic)),
          name_latin: String.trim(string(params, "name_latin", parent.name_latin)),
          country: country
        )

      {:ok, Repo.update!(parent)}
    end
  end

  def delete_parent(company_id, id) do
    with {:ok, parent} <- load(company_id, Parent, id, "предприятието майка не е намерено") do
      Repo.delete!(parent)
      {:ok, nil}
    end
  end

  ## Серии

  def create_series(company_id, params) do
    with {:ok, name} <- required(params, "name", "name е задължително"),
         {:ok, types} <- types_csv(params),
         {:ok, pad} <- pad_width(params),
         {:ok, start} <- start_number(params),
         next_number <- next_out_number(company_id, types, start, pad) do
      series = %Series{
        company_id: company_id,
        name: String.trim(name),
        document_types: types,
        pad_width: pad,
        start_number: start,
        next_number: next_number
      }

      series = Repo.insert!(series)
      steal_types(company_id, series.id, types)
      {:ok, Repo.get!(Series, series.id)}
    end
  end

  def update_series(company_id, id, params) do
    with {:ok, series} <- load(company_id, Series, id, "серията не е намерена"),
         {:ok, name} <- required(params, "name", "name е задължително", series.name),
         {:ok, types} <- types_csv(params, series.document_types),
         {:ok, pad} <- pad_width(params, series.pad_width),
         {:ok, start} <- start_number(params, series.start_number) do
      types_changed = Map.has_key?(params, "document_types")
      pad_changed = Map.has_key?(params, "pad_width")
      start_changed = Map.has_key?(params, "start_number")

      next_number =
        if types_changed or pad_changed or start_changed,
          do: next_out_number(company_id, types, start, pad),
          else: series.next_number

      series =
        Ecto.Changeset.change(series,
          name: String.trim(name),
          document_types: types,
          pad_width: pad,
          start_number: start,
          next_number: next_number
        )
        |> Repo.update!()

      if types_changed, do: steal_types(company_id, id, types)
      {:ok, Repo.get!(Series, series.id)}
    end
  end

  def delete_series(company_id, id) do
    with {:ok, series} <- load(company_id, Series, id, "серията не е намерена") do
      Repo.delete!(series)
      {:ok, nil}
    end
  end

  @doc "Следващият номер на изходящ документ от серията."
  def next_out_number(company_id, types, start, pad) do
    want = csv_parts(types)

    max =
      Botyaga.Invoicing.Invoice
      |> where([i], i.company_id == ^company_id and i.direction == "out")
      |> select([i], {i.document_type, i.number})
      |> Repo.all()
      |> Enum.filter(fn {type, _number} -> type in want end)
      |> Enum.map(fn {_type, number} -> to_int(number) end)
      |> Enum.max(fn -> max(start - 1, 0) end)

    pad_num(max + 1, pad)
  end

  defp steal_types(company_id, keep_id, types) do
    drop = csv_parts(types)

    if drop != [] do
      Series
      |> where([s], s.company_id == ^company_id and s.id != ^keep_id)
      |> select([s], s)
      |> Repo.all()
      |> Enum.each(fn series ->
        kept = series.document_types |> csv_parts() |> Enum.reject(&(&1 in drop))

        if kept != csv_parts(series.document_types) do
          series
          |> Ecto.Changeset.change(document_types: Enum.join(kept, ","))
          |> Repo.update!()
        end
      end)
    end
  end

  ## Общи помощници

  defp load(company_id, schema, id, message) do
    case Repo.get_by(schema, id: id, company_id: company_id) do
      nil -> {:error, {404, message}}
      record -> {:ok, record}
    end
  end

  defp required(params, key, message, current \\ nil)

  defp required(params, key, message, nil) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "", do: {:error, {422, message}}, else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, message}}
    end
  end

  defp required(params, key, message, current) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "", do: {:error, {422, message}}, else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:ok, current}
    end
  end

  defp location_type(params, current \\ nil) do
    case Params.str(params, "location_type") do
      :absent ->
        {:ok, current || "OFFICE"}

      {:present, value} ->
        type = String.trim(value)
        type = if type == "", do: "OFFICE", else: type

        if type in @location_types, do: {:ok, type}, else: {:error, {422, @location_message}}

      {:error, _} ->
        {:error, {422, @location_message}}
    end
  end

  defp country(params, current \\ nil) do
    case Params.str(params, "country") do
      :absent ->
        {:ok, current || "BG"}

      {:present, value} ->
        value = String.trim(value)
        {:ok, if(value == "", do: "BG", else: value)}

      {:error, _} ->
        {:error, {422, "country трябва да е низ"}}
    end
  end

  defp types_csv(params, current \\ nil) do
    case Params.types_csv(params) do
      nil -> {:ok, current || ""}
      {:error, message} -> {:error, {422, message}}
      value -> {:ok, value}
    end
  end

  defp pad_width(params, current \\ 10) do
    case Params.integer(params, "pad_width") do
      nil -> {:ok, current}
      {:error, message} -> {:error, {422, message}}
      value -> {:ok, clamp(value, 1, 10)}
    end
  end

  defp start_number(params, current \\ 1) do
    case Params.integer(params, "start_number") do
      nil -> {:ok, current}
      {:error, message} -> {:error, {422, message}}
      value -> {:ok, max(value, 1)}
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end

  defp flag(params, key, default \\ 0) do
    case Params.flag(params, key) do
      nil -> default
      {:error, _} -> default
      value -> value
    end
  end

  defp csv_parts(types) do
    types
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp pad_num(number, width) do
    number |> max(0) |> to_string() |> String.pad_leading(width, "0")
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)

  defp to_int(nil), do: 0

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

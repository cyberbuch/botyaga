defmodule Botyaga.Assets do
  @moduledoc "Дълготрайни активи и категории. Сумите остават низ."

  import Ecto.Query

  alias Botyaga.{Companies, Dec, Params, Repo}
  alias Botyaga.Assets.{Asset, Category}

  ## Категории

  def categories(company_id) do
    Repo.all(from(c in Category, where: c.company_id == ^company_id, order_by: [asc: c.id]))
    |> Enum.map(&category_json/1)
  end

  def category_create(company_id, params) do
    with {:ok, name} <- required(params, "name"),
         {:ok, min} <- rate(params, "min_depreciation_rate", "0"),
         {:ok, max} <- rate(params, "max_depreciation_rate", "0") do
      category = %Category{
        company_id: company_id,
        name: name,
        cita_category: string(params, "cita_category"),
        min_depreciation_rate: min,
        max_depreciation_rate: max,
        default_method: string(params, "default_method", "linear")
      }

      {:ok, category_json(Repo.insert!(category))}
    end
  end

  def category_update(company_id, id, params) do
    with {:ok, category} <- fetch_category(company_id, id),
         {:ok, name} <- pick(params, "name", category.name),
         :ok <- present(name, "name"),
         {:ok, min} <- pick_rate(params, "min_depreciation_rate", category.min_depreciation_rate),
         {:ok, max} <- pick_rate(params, "max_depreciation_rate", category.max_depreciation_rate) do
      category =
        Repo.update!(
          Ecto.Changeset.change(category,
            name: name,
            cita_category: pick_string(params, "cita_category", category.cita_category),
            min_depreciation_rate: min,
            max_depreciation_rate: max,
            default_method: pick_string(params, "default_method", category.default_method)
          )
        )

      {:ok, category_json(category)}
    end
  end

  def category_delete(company_id, id) do
    with {:ok, category} <- fetch_category(company_id, id) do
      Repo.delete!(category)
      {:ok, nil}
    end
  end

  defp fetch_category(company_id, id) do
    case Repo.get_by(Category, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "Категорията не е намерена"}}
      category -> {:ok, category}
    end
  end

  defp category_json(c) do
    %{
      id: c.id,
      name: c.name,
      cita_category: c.cita_category,
      min_depreciation_rate: c.min_depreciation_rate,
      max_depreciation_rate: c.max_depreciation_rate,
      default_method: c.default_method
    }
  end

  ## Активи

  def list(company_id) do
    Repo.all(from(a in Asset, where: a.company_id == ^company_id, order_by: [asc: a.id]))
    |> Enum.map(&asset_json/1)
  end

  def get(company_id, id) do
    case fetch(company_id, id) do
      {:ok, asset} -> {:ok, asset_json(asset)}
      error -> error
    end
  end

  def create(company_id, params) do
    with {:ok, fields} <- fields(params, nil),
         :ok <- ensure_ref(Category, fields.category_id, company_id, "записът"),
         :ok <- ensure_ref(Companies.Location, fields.location_id, company_id, "обектът") do
      asset =
        struct(
          %Asset{
            company_id: company_id,
            accumulated_depreciation: "0.00",
            tax_accumulated_depreciation: "0.00"
          },
          fields
        )

      {:ok, asset_json(Repo.insert!(asset))}
    end
  end

  def update(company_id, id, params) do
    with {:ok, current} <- fetch(company_id, id),
         {:ok, fields} <- fields(params, current),
         :ok <- ensure_ref(Category, fields.category_id, company_id, "записът"),
         :ok <- ensure_ref(Companies.Location, fields.location_id, company_id, "обектът") do
      {:ok, asset_json(Repo.update!(Ecto.Changeset.change(current, fields)))}
    end
  end

  def delete(company_id, id) do
    with {:ok, asset} <- fetch(company_id, id) do
      Repo.delete_all(from(e in Botyaga.Assets.Event, where: e.asset_id == ^asset.id))
      Repo.delete!(asset)
      {:ok, nil}
    end
  end

  def fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Asset, id: id, company_id: company_id) do
        nil -> {:error, {404, "Активът не е намерен"}}
        asset -> {:ok, asset}
      end
    end
  end

  def asset_json(a) do
    base = %{
      id: a.id,
      name: a.name,
      inventory_number: a.inventory_number,
      acquisition_date: a.acquisition_date,
      put_into_service_date: a.put_into_service_date,
      cost: a.cost,
      salvage_value: a.salvage_value,
      useful_life_months: a.useful_life_months,
      depreciation_method: a.depreciation_method,
      accounting_depreciation_rate: a.accounting_depreciation_rate,
      tax_depreciation_rate: a.tax_depreciation_rate,
      accumulated_depreciation: a.accumulated_depreciation,
      tax_accumulated_depreciation: a.tax_accumulated_depreciation,
      status: a.status,
      serial_number: a.serial_number,
      manufacturer: a.manufacturer,
      model: a.model,
      responsible_person: a.responsible_person,
      is_conserved: a.is_conserved,
      location_id: a.location_id,
      company_id: a.company_id
    }

    if a.category_id > 0, do: Map.put(base, :category_id, a.category_id), else: base
  end

  defp fields(params, current) do
    with {:ok, name} <- pick(params, "name", (current && current.name) || ""),
         :ok <- present(name, "name"),
         {:ok, cost} <- money_of(pick_string(params, "cost", (current && current.cost) || "0")),
         {:ok, salvage} <-
           money_of(
             pick_string(params, "salvage_value", (current && current.salvage_value) || "0")
           ),
         {:ok, acc_rate} <-
           money_rate(
             pick_string(
               params,
               "accounting_depreciation_rate",
               (current && current.accounting_depreciation_rate) || "0"
             )
           ),
         {:ok, tax_rate} <-
           money_rate(
             pick_string(
               params,
               "tax_depreciation_rate",
               (current && current.tax_depreciation_rate) || "0"
             )
           ) do
      {:ok,
       %{
         name: name,
         inventory_number:
           pick_string(params, "inventory_number", (current && current.inventory_number) || ""),
         category_id: pick_int(params, "category_id", current && current.category_id),
         acquisition_date:
           pick_string(params, "acquisition_date", (current && current.acquisition_date) || ""),
         put_into_service_date:
           pick_string(
             params,
             "put_into_service_date",
             (current && current.put_into_service_date) || ""
           ),
         cost: cost,
         salvage_value: salvage,
         useful_life_months:
           pick_string(
             params,
             "useful_life_months",
             (current && current.useful_life_months) || "0"
           ),
         depreciation_method:
           pick_string(
             params,
             "depreciation_method",
             (current && current.depreciation_method) || "linear"
           ),
         accounting_depreciation_rate: acc_rate,
         tax_depreciation_rate: tax_rate,
         status: pick_string(params, "status", (current && current.status) || "active"),
         serial_number:
           pick_string(params, "serial_number", (current && current.serial_number) || ""),
         manufacturer:
           pick_string(params, "manufacturer", (current && current.manufacturer) || ""),
         model: pick_string(params, "model", (current && current.model) || ""),
         responsible_person:
           pick_string(
             params,
             "responsible_person",
             (current && current.responsible_person) || ""
           ),
         is_conserved: pick_flag(params, "is_conserved", current && current.is_conserved),
         location_id: pick_int(params, "location_id", current && current.location_id)
       }}
    end
  end

  defp ensure_ref(_schema, id, _company_id, _what) when id <= 0, do: :ok

  defp ensure_ref(schema, id, company_id, what) do
    if Repo.get_by(schema, id: id, company_id: company_id) == nil do
      {:error, {404, "#{what} не е намерен"}}
    else
      :ok
    end
  end

  defp money_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна стойност"}}
      value -> {:ok, Dec.money(value)}
    end
  end

  defp money_rate(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна норма"}}
      value -> {:ok, Dec.text(value, 4)}
    end
  end

  defp rate(params, key, default) do
    money_rate(string(params, key, default))
  end

  defp pick_rate(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> money_rate(value)
      _ -> {:ok, current}
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> {:ok, value}
      _ -> {:ok, current}
    end
  end

  defp pick_string(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  defp pick_int(params, key, current) do
    case Params.integer(params, key) do
      nil -> current || 0
      {:error, _} -> current || 0
      value -> value
    end
  end

  defp pick_flag(params, key, current) do
    case Params.flag(params, key) do
      nil -> current || 0
      {:error, _} -> current || 0
      value -> value
    end
  end

  defp present(value, key) do
    if String.trim(value || "") == "", do: {:error, {422, "#{key} е задължително"}}, else: :ok
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

defmodule Botyaga.Assets.Asset do
  use Ecto.Schema

  schema "fixed_assets" do
    field :company_id, :id
    field :name, :string
    field :inventory_number, :string
    field :category_id, :integer, default: 0
    field :acquisition_date, :string
    field :put_into_service_date, :string
    field :cost, :string
    field :salvage_value, :string
    field :useful_life_months, :string
    field :depreciation_method, :string
    field :accounting_depreciation_rate, :string
    field :tax_depreciation_rate, :string
    field :accumulated_depreciation, :string
    field :tax_accumulated_depreciation, :string
    field :status, :string
    field :serial_number, :string
    field :manufacturer, :string
    field :model, :string
    field :responsible_person, :string
    field :is_conserved, :integer, default: 0
    field :location_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

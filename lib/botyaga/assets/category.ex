defmodule Botyaga.Assets.Category do
  use Ecto.Schema

  schema "fixed_asset_categories" do
    field :company_id, :id
    field :name, :string
    field :cita_category, :string
    field :min_depreciation_rate, :string
    field :max_depreciation_rate, :string
    field :default_method, :string
    field :asset_account_id, :integer, default: 0
    field :depreciation_account_id, :integer, default: 0
    field :expense_account_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Catalog.Product do
  use Ecto.Schema

  schema "products" do
    field :company_id, :id
    field :name, :string
    field :code, :string
    field :description, :string
    field :unit, :string, default: "C62"
    field :price, :string, default: "0"
    field :cost_price, :string, default: "0"
    field :vat_rate, :string, default: "20"
    field :is_service, :integer, default: 0
    field :is_inventory, :integer, default: 0
    field :inventory_account_id, :integer, default: 0
    field :revenue_account_id, :integer, default: 0
    field :stock_quantity, :string, default: "0"
    field :stock_value, :string, default: "0"
    field :is_active, :integer, default: 1
    field :product_type, :string
    field :cn8_code, :string
    field :cn8_name, :string
    field :expense_account_id, :integer, default: 0
    field :auto_write_off, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

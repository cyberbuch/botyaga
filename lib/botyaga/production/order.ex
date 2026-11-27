defmodule Botyaga.Production.Order do
  use Ecto.Schema

  schema "production_orders" do
    field :company_id, :id
    field :number, :string
    field :recipe_id, :integer, default: 0
    field :output_product_id, :integer, default: 0
    field :quantity, :string
    field :location_id, :integer, default: 0
    field :order_date, :string
    field :status, :string
    field :notes, :string
    field :material_cost, :string
    field :journal_entry_id, :integer, default: 0
    field :recipe_snapshot, :string

    timestamps(type: :utc_datetime)
  end
end

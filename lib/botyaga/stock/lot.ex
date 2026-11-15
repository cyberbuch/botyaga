defmodule Botyaga.Stock.Lot do
  use Ecto.Schema

  schema "inventory_lots" do
    field :product_id, :integer
    field :invoice_id, :integer, default: 0
    field :invoice_line_id, :integer, default: 0
    field :received_date, :string
    field :quantity, :string
    field :quantity_remaining, :string
    field :unit_cost, :string
    field :location_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

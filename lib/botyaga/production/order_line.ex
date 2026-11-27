defmodule Botyaga.Production.OrderLine do
  use Ecto.Schema

  schema "production_order_lines" do
    field :order_id, :integer
    field :product_id, :integer
    field :product_name, :string
    field :quantity, :string
    field :norm_quantity, :string, default: "0"
    field :unit, :string
    field :unit_cost, :string
    field :amount, :string

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Production.Recipe do
  use Ecto.Schema

  schema "recipes" do
    field :company_id, :id
    field :code, :string
    field :name, :string
    field :output_product_id, :integer, default: 0
    field :output_quantity, :string
    field :output_unit, :string
    field :notes, :string
    field :is_active, :integer, default: 1
    field :kind, :string, default: "production"

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Production.RecipeLine do
  use Ecto.Schema

  schema "recipe_lines" do
    field :recipe_id, :integer
    field :product_id, :integer
    field :quantity, :string
    field :unit, :string
    field :wastage_percent, :string
    field :line_no, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

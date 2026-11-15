defmodule Botyaga.Stock.InternalDocLine do
  use Ecto.Schema

  schema "internal_doc_lines" do
    field :doc_id, :integer
    field :line_kind, :string
    field :product_id, :integer, default: 0
    field :asset_id, :integer, default: 0
    field :quantity, :string
    field :unit_cost, :string
    field :amount, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end
end

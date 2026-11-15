defmodule Botyaga.Stock.MaterialIssueLine do
  use Ecto.Schema

  schema "material_issue_lines" do
    field :doc_id, :integer
    field :product_id, :integer
    field :quantity, :string
    field :unit_cost, :string
    field :amount, :string
    field :account_id, :integer, default: 0
    field :inventory_account_id, :integer, default: 0
    field :line_no, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

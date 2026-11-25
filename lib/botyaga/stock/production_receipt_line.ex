defmodule Botyaga.Stock.ProductionReceiptLine do
  use Ecto.Schema

  schema "production_receipt_lines" do
    field :doc_id, :integer
    field :line_no, :integer, default: 0
    field :product_id, :integer
    field :sold_quantity, :string, default: "0"
    field :sold_amount, :string, default: "0.00"
    field :ending_quantity, :string, default: "0"
    field :quantity, :string, default: "0"
    field :unit_cost, :string, default: "0.000000"
    field :amount, :string, default: "0.00"
    field :allocated_amount, :string, default: "0.00"
    field :writeoff_amount, :string, default: "0.00"
    field :inventory_account_id, :integer, default: 0
    field :revenue_account_id, :integer, default: 0
    field :expense_account_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

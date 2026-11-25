defmodule Botyaga.Stock.ProductionReceiptAllocation do
  use Ecto.Schema

  schema "production_receipt_allocations" do
    field :doc_id, :integer
    field :line_no, :integer, default: 0
    field :product_id, :integer
    field :account_id, :integer
    field :base_amount, :string, default: "0.00"
    field :amount, :string, default: "0.00"

    timestamps(type: :utc_datetime)
  end
end

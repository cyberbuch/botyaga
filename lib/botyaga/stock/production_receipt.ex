defmodule Botyaga.Stock.ProductionReceipt do
  use Ecto.Schema

  schema "production_receipts" do
    field :company_id, :id
    field :number, :string
    field :doc_date, :string
    field :month, :string
    field :status, :string
    field :notes, :string
    field :journal_entry_id, :integer, default: 0
    field :wip_end_mode, :string, default: "amount"
    field :wip_end_value, :string, default: "0"

    timestamps(type: :utc_datetime)
  end
end

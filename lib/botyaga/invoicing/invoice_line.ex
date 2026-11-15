defmodule Botyaga.Invoicing.InvoiceLine do
  use Ecto.Schema

  schema "invoice_lines" do
    field :invoice_id, :id
    field :code, :string
    field :description, :string
    field :quantity, :string
    field :unit, :string
    field :unit_price, :string
    field :vat_rate, :string
    field :net_amount, :string
    field :vat_amount, :string
    field :total_amount, :string
    field :product_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

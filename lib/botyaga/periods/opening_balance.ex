defmodule Botyaga.Periods.OpeningBalance do
  use Ecto.Schema

  schema "opening_balances" do
    field :company_id, :id
    field :fiscal_year, :integer
    field :account_id, :integer
    field :debit, :string
    field :credit, :string
    field :counterpart_id, :integer, default: 0
    field :product_id, :integer, default: 0
    field :quantity, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end
end

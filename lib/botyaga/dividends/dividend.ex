defmodule Botyaga.Dividends.Dividend do
  use Ecto.Schema

  schema "dividends" do
    field :company_id, :id
    field :distribution_id, :integer
    field :beneficial_owner_id, :integer, default: 0
    field :owner_name, :string
    field :owner_egn, :string
    field :ownership_percentage, :string
    field :gross_amount, :string
    field :tax_rate, :string
    field :tax_amount, :string
    field :net_amount, :string
    field :decision_date, :string
    field :payment_date, :string
    field :is_paid, :integer, default: 0
    field :notes, :string

    timestamps(type: :utc_datetime)
  end
end

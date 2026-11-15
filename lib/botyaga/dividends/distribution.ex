defmodule Botyaga.Dividends.Distribution do
  use Ecto.Schema

  schema "dividend_distributions" do
    field :company_id, :id
    field :year, :integer
    field :total_amount, :string
    field :decision_date, :string
    field :decision_number, :string
    field :status, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Periods.Period do
  use Ecto.Schema

  schema "accounting_periods" do
    field :company_id, :id
    field :year, :integer
    field :month, :integer
    field :status, :string
    field :closed_at, :string
    field :notes, :string

    timestamps(type: :utc_datetime)
  end
end

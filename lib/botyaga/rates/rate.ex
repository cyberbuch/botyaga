defmodule Botyaga.Rates.Rate do
  use Ecto.Schema

  schema "exchange_rates" do
    field :code, :string
    field :rate, :string
    field :date, :string

    timestamps(type: :utc_datetime)
  end
end

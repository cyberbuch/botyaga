defmodule Botyaga.Journal.Line do
  use Ecto.Schema

  schema "journal_lines" do
    field :entry_id, :id
    field :account_id, :integer
    field :account_number, :string
    field :account_name, :string
    field :direction, :string
    field :amount, :string
    field :vat_amount, :string
    field :currency, :string
    field :fx_quantity, :string
    field :fx_rate, :string

    timestamps(type: :utc_datetime)
  end
end

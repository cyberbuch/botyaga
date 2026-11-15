defmodule Botyaga.Banking.Transaction do
  use Ecto.Schema

  schema "bank_transactions" do
    field :company_id, :id
    field :bank_account_id, :integer
    field :txn_date, :string
    field :amount, :string
    field :currency, :string
    field :counterpart_name, :string
    field :counterpart_iban, :string
    field :description, :string
    field :reference, :string
    field :transaction_type, :string
    field :is_booked, :integer, default: 0
    field :is_allocated, :integer, default: 0
    field :journal_entry_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

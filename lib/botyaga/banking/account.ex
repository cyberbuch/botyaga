defmodule Botyaga.Banking.Account do
  use Ecto.Schema

  schema "bank_accounts" do
    field :company_id, :id
    field :iban, :string
    field :bic, :string
    field :bank_name, :string
    field :currency, :string
    field :name, :string
    field :account_number, :string
    field :gl_account_id, :integer, default: 0
    field :buffer_account_id, :integer, default: 0
    field :balance, :string

    timestamps(type: :utc_datetime)
  end
end

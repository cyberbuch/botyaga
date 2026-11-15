defmodule Botyaga.Catalog.Account do
  use Ecto.Schema

  schema "accounts" do
    field :company_id, :id
    field :number, :string
    field :name, :string
    field :saft_account_type, :string
    field :analytic_type, :string, default: "none"
    field :is_currency, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

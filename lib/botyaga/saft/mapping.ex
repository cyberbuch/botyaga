defmodule Botyaga.Saft.Mapping do
  use Ecto.Schema

  schema "saft_account_mappings" do
    field :company_id, :id
    field :kind, :string
    field :type_code, :string
    field :debit_account, :string
    field :credit_account, :string
    field :debit_analytical, :string
    field :credit_analytical, :string
    field :description, :string
    field :is_active, :integer, default: 1

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Stock.Rule do
  use Ecto.Schema

  schema "stock_account_rules" do
    field :company_id, :id
    field :kind, :string
    field :inventory_account_id, :integer, default: 0
    field :offset_account_id, :integer, default: 0
    field :clearing_account_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

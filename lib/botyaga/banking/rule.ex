defmodule Botyaga.Banking.Rule do
  use Ecto.Schema

  schema "bank_matching_rules" do
    field :company_id, :id
    field :name, :string
    field :keywords, :string
    field :direction, :string
    field :priority, :integer
    field :is_active, :integer, default: 1
    field :account_id, :integer, default: 0
    field :counterpart_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Accounts.RecoveryCode do
  use Ecto.Schema

  schema "user_recovery_codes" do
    field :user_id, :id
    field :code_hash, :string
    field :used, :integer, default: 0
  end
end

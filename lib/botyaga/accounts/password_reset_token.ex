defmodule Botyaga.Accounts.PasswordResetToken do
  use Ecto.Schema

  schema "password_reset_tokens" do
    field :user_id, :id
    field :token_hash, :string
    field :expires_at, :integer
    field :used, :integer, default: 0
  end
end

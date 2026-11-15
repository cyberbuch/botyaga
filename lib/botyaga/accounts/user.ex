defmodule Botyaga.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :name, :string
    field :username, :string
    field :password_hash, :string
    field :role, :string, default: "user"
    field :is_active, :integer, default: 1
    field :is_super_admin, :integer, default: 0
    field :role_id, :integer, default: 0
    field :totp_enabled, :integer, default: 0
    field :totp_secret_b32, :string
    field :totp_pending_b32, :string
    field :session_version, :integer, default: 0
    field :mfa_fails, :integer, default: 0
    field :mfa_lock_until, :integer, default: 0
    field :created_at, :utc_datetime
  end
end

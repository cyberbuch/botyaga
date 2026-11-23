defmodule Botyaga.Accounts.LoginEvent do
  use Ecto.Schema

  schema "login_events" do
    field :user_id, :integer, default: 0
    field :user_login, :string, default: ""
    field :event, :string
    field :ip, :string, default: ""
    field :user_agent, :string, default: ""
    field :detail, :string, default: ""
    field :created_at, :utc_datetime
  end
end

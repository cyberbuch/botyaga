defmodule Botyaga.Access.Membership do
  use Ecto.Schema

  schema "user_companies" do
    field :user_id, :id
    field :company_id, :id
    field :role_id, :id
    field :created_at, :utc_datetime
  end
end

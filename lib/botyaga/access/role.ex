defmodule Botyaga.Access.Role do
  use Ecto.Schema

  schema "roles" do
    field :name, :string
    field :description, :string
    field :permissions, :string
    field :created_at, :utc_datetime
  end
end

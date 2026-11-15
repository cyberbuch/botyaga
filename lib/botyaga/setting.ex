defmodule Botyaga.Setting do
  use Ecto.Schema

  schema "settings" do
    field :setting_key, :string
    field :value, :string
  end
end

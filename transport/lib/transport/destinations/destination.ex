defmodule Transport.Destinations.Destination do
  use Ecto.Schema

  schema "destinations" do
    field :country, :string
    field :city, :string, default: ""
    field :kind, :string, default: "abroad"
    field :per_diem, :string, default: "0"
    field :per_diem_no_overnight, :string, default: "0"
    field :lodging_limit, :string, default: "0"
    field :active, :integer, default: 1
    timestamps(type: :utc_datetime)
  end
end

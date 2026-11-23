defmodule Transport.Vehicles.Vehicle do
  use Ecto.Schema

  schema "vehicles" do
    field :company_id, :integer
    field :name, :string
    field :plate, :string, default: ""
    field :fuel, :string, default: "Дизел"
    field :norm, :string, default: "0"
    field :winter_surcharge, :integer, default: 0
    field :tank_volume, :string, default: ""
    field :active, :integer, default: 1
    field :note, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

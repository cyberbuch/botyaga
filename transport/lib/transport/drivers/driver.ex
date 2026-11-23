defmodule Transport.Drivers.Driver do
  use Ecto.Schema

  schema "drivers" do
    field :company_id, :integer
    field :name, :string
    field :egn, :string, default: ""
    field :license_number, :string, default: ""
    field :phone, :string, default: ""
    field :active, :integer, default: 1
    field :note, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

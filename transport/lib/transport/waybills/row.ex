defmodule Transport.Waybills.Row do
  use Ecto.Schema

  schema "waybill_rows" do
    field :waybill_id, :integer
    field :kind, :string, default: "route"
    field :date, :string, default: ""
    field :description, :string, default: ""
    field :city_km, :string, default: "0"
    field :out_km, :string, default: "0"
    field :winter, :integer, default: 0
    field :fuel_liters, :string, default: "0"
    field :fuel_cost, :string, default: "0"
  end
end

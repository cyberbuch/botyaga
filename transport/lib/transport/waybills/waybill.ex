defmodule Transport.Waybills.Waybill do
  use Ecto.Schema

  schema "waybills" do
    field :company_id, :integer
    field :number, :string, default: ""
    field :vehicle_id, :integer, default: 0
    field :driver_id, :integer, default: 0
    field :approver, :string, default: ""
    field :date, :string, default: ""
    field :start_odometer, :string, default: "0"
    field :start_fuel, :string, default: "0"
    field :end_odometer, :string, default: ""
    field :end_fuel, :string, default: ""
    field :status, :string, default: "open"
    field :note, :string, default: ""
    field :norm, :string, default: ""
    field :winter_surcharge, :integer, default: 0
    field :total_km, :string, default: ""
    field :total_refuel, :string, default: ""
    field :norm_consumption, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

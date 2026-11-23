defmodule Transport.Trips.Trip do
  use Ecto.Schema

  schema "trips" do
    field :company_id, :integer
    field :number, :string, default: ""
    field :worker_name, :string, default: ""
    field :destination_id, :integer, default: 0
    field :start_date, :string, default: ""
    field :end_date, :string, default: ""
    field :days, :integer, default: 0
    field :overnight, :integer, default: 1
    field :per_diem_rate, :string, default: "0"
    field :per_diem_total, :string, default: "0"
    field :lodging, :string, default: "0"
    field :lodging_limit, :string, default: "0"
    field :transport_cost, :string, default: "0"
    field :advance, :string, default: "0"
    field :status, :string, default: "draft"
    field :note, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

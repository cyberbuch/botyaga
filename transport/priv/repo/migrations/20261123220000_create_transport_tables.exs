defmodule Transport.Repo.Migrations.CreateTransportTables do
  use Ecto.Migration

  def change do
    create table(:vehicles) do
      add :company_id, :bigint, null: false
      add :name, :string, null: false
      add :plate, :string, default: "", null: false
      add :fuel, :string, default: "Дизел", null: false
      add :norm, :string, default: "0", null: false
      add :winter_surcharge, :integer, default: 0, null: false
      add :tank_volume, :string, default: "", null: false
      add :active, :integer, default: 1, null: false
      add :note, :string, default: "", null: false
      timestamps(type: :utc_datetime)
    end

    create index(:vehicles, [:company_id])

    create table(:drivers) do
      add :company_id, :bigint, null: false
      add :name, :string, null: false
      add :egn, :string, default: "", null: false
      add :license_number, :string, default: "", null: false
      add :phone, :string, default: "", null: false
      add :active, :integer, default: 1, null: false
      add :note, :string, default: "", null: false
      timestamps(type: :utc_datetime)
    end

    create index(:drivers, [:company_id])

    create table(:destinations) do
      add :country, :string, null: false
      add :city, :string, default: "", null: false
      add :kind, :string, default: "abroad", null: false
      add :per_diem, :string, default: "0", null: false
      add :per_diem_no_overnight, :string, default: "0", null: false
      add :lodging_limit, :string, default: "0", null: false
      add :active, :integer, default: 1, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:waybills) do
      add :company_id, :bigint, null: false
      add :number, :string, default: "", null: false
      add :vehicle_id, :bigint, default: 0, null: false
      add :driver_id, :bigint, default: 0, null: false
      add :approver, :string, default: "", null: false
      add :date, :string, default: "", null: false
      add :start_odometer, :string, default: "0", null: false
      add :start_fuel, :string, default: "0", null: false
      add :end_odometer, :string, default: "", null: false
      add :end_fuel, :string, default: "", null: false
      add :status, :string, default: "open", null: false
      add :note, :string, default: "", null: false
      timestamps(type: :utc_datetime)
    end

    create index(:waybills, [:company_id])

    create table(:waybill_rows) do
      add :waybill_id, references(:waybills, on_delete: :delete_all), null: false
      add :kind, :string, default: "route", null: false
      add :date, :string, default: "", null: false
      add :description, :string, default: "", null: false
      add :city_km, :string, default: "0", null: false
      add :out_km, :string, default: "0", null: false
      add :winter, :integer, default: 0, null: false
      add :fuel_liters, :string, default: "0", null: false
      add :fuel_cost, :string, default: "0", null: false
    end

    create index(:waybill_rows, [:waybill_id])

    create table(:trips) do
      add :company_id, :bigint, null: false
      add :number, :string, default: "", null: false
      add :worker_name, :string, default: "", null: false
      add :destination_id, :bigint, default: 0, null: false
      add :start_date, :string, default: "", null: false
      add :end_date, :string, default: "", null: false
      add :days, :integer, default: 0, null: false
      add :overnight, :integer, default: 1, null: false
      add :per_diem_rate, :string, default: "0", null: false
      add :per_diem_total, :string, default: "0", null: false
      add :lodging, :string, default: "0", null: false
      add :lodging_limit, :string, default: "0", null: false
      add :transport_cost, :string, default: "0", null: false
      add :advance, :string, default: "0", null: false
      add :status, :string, default: "draft", null: false
      add :note, :string, default: "", null: false
      timestamps(type: :utc_datetime)
    end

    create index(:trips, [:company_id])
  end
end

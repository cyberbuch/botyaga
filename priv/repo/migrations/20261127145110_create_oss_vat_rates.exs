defmodule Botyaga.Repo.Migrations.CreateOssVatRates do
  use Ecto.Migration

  def change do
    create table(:oss_vat_rates) do
      add :company_id, :bigint, null: false
      add :country, :string, null: false
      add :account_id, :bigint, null: false, default: 0
      add :rate, :string, null: false, default: "0"
      add :rate_kind, :string, null: false, default: "standard"
      add :supply_kind, :string, null: false, default: "goods"
      add :valid_from, :string, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create index(:oss_vat_rates, [:company_id, :country])
  end
end

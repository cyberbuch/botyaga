defmodule Botyaga.Repo.Migrations.CreateVatOperations do
  use Ecto.Migration

  def change do
    create table(:vat_operations) do
      add :company_id, :bigint, null: false
      add :name, :string, null: false
      add :category, :string, null: false
      add :code, :integer, null: false, default: 0
      add :additional, :integer, null: false, default: 0
      add :rate, :string, null: false, default: "20"
      add :counterpart_account_id, :bigint, null: false, default: 0
      add :vat_account_id, :bigint, null: false, default: 0
      add :protocol, :string, null: false, default: ""
      add :oss_country, :string, null: false, default: ""
      add :oss_rate_kind, :string, null: false, default: ""
      add :oss_supply_kind, :string, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create index(:vat_operations, [:company_id])
    create unique_index(:vat_operations, [:company_id, :category, :name])
  end
end

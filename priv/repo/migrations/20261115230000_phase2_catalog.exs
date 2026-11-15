defmodule Botyaga.Repo.Migrations.Phase2Catalog do
  use Ecto.Migration

  def change do
    # counterpart_extra е слят тук — Octo нямаше ALTER TABLE, Postgres има.
    create table(:counterparts) do
      add :company_id, :bigint, null: false
      add :name, :string
      add :counterpart_type, :string, default: "both"
      add :eik, :string
      add :vat_number, :string
      add :address, :string
      add :city, :string
      add :post_code, :string
      add :country, :string, default: "BG"
      add :contact_person, :string
      add :vies_address, :string
      add :street_name, :string
      add :building_number, :string
      add :address_building, :string
      add :additional_address_detail, :string
      add :address_type, :string
      add :region, :string
      add :email, :string
      add :phone, :string

      timestamps(type: :utc_datetime)
    end

    create index(:counterparts, [:company_id])

    # product_extra е слят тук. Парите остават низове — API-то връща подаденото.
    create table(:products) do
      add :company_id, :bigint, null: false
      add :name, :string
      add :code, :string
      add :description, :string
      add :unit, :string, default: "C62"
      add :price, :string, default: "0"
      add :cost_price, :string, default: "0"
      add :vat_rate, :string, default: "20"
      add :is_service, :integer, default: 0
      add :is_inventory, :integer, default: 0
      add :inventory_account_id, :bigint, default: 0
      add :revenue_account_id, :bigint, default: 0
      add :stock_quantity, :string, default: "0"
      add :stock_value, :string, default: "0"
      add :is_active, :integer, default: 1
      add :product_type, :string
      add :cn8_code, :string
      add :cn8_name, :string
      add :expense_account_id, :bigint, default: 0
      add :auto_write_off, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:company_id])
  end
end

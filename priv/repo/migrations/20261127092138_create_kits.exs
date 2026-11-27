defmodule Botyaga.Repo.Migrations.CreateKits do
  use Ecto.Migration

  def change do
    create table(:kits) do
      add :company_id, :bigint, null: false
      add :number, :string, null: false, default: ""
      add :doc_date, :string, null: false, default: ""
      add :status, :string, null: false, default: "draft"
      add :kind, :string, null: false, default: "kit_goods"
      add :output_product_id, :bigint, null: false, default: 0
      add :quantity, :string, null: false, default: "0"
      add :location_id, :bigint, null: false, default: 0
      add :recipe_id, :bigint, null: false, default: 0
      add :cost, :string, null: false, default: "0.00"
      add :journal_entry_id, :bigint, null: false, default: 0
      add :notes, :string, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create index(:kits, [:company_id])

    create table(:kit_lines) do
      add :kit_id, references(:kits, on_delete: :delete_all), null: false
      add :product_id, :bigint, null: false
      add :quantity, :string, null: false, default: "0"
    end

    create index(:kit_lines, [:kit_id])

    alter table(:recipes) do
      add :kind, :string, null: false, default: "production"
    end
  end
end

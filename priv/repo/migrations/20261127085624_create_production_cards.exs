defmodule Botyaga.Repo.Migrations.CreateProductionCards do
  use Ecto.Migration

  def change do
    create table(:production_cards) do
      add :company_id, :bigint, null: false
      add :number, :string, null: false, default: ""
      add :month, :string, null: false, default: ""
      add :status, :string, null: false, default: "draft"
      add :materials_account_id, :bigint, null: false, default: 0
      add :production_account_id, :bigint, null: false, default: 0
      add :direct_accounts, :text
      add :common_accounts, :text
      add :common_share_percent, :string, null: false, default: "100"
      add :wip_end_mode, :string, null: false, default: "amount"
      add :wip_end_value, :string, null: false, default: "0"
      add :journal_entry_id, :bigint, null: false, default: 0
      add :notes, :string, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create index(:production_cards, [:company_id])

    create table(:production_card_products) do
      add :card_id, references(:production_cards, on_delete: :delete_all), null: false
      add :product_id, :bigint, null: false
      add :quantity, :string, null: false, default: "0"
      add :coefficient, :string, null: false, default: "1"
      add :manual_amount, :string, null: false, default: ""
      add :cost, :string, null: false, default: "0"
      add :inventory_account_id, :bigint, null: false, default: 0
    end

    create index(:production_card_products, [:card_id])
  end
end

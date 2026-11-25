defmodule Botyaga.Repo.Migrations.CreateProductionReceipts do
  use Ecto.Migration

  def change do
    create table(:production_receipts) do
      add :company_id, :bigint, null: false
      add :number, :string
      add :doc_date, :string
      add :month, :string
      add :status, :string
      add :notes, :string
      add :journal_entry_id, :bigint, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:production_receipts, [:company_id])
    create index(:production_receipts, [:company_id, :month])

    create table(:production_receipt_lines) do
      add :doc_id, :bigint, null: false
      add :line_no, :integer, default: 0
      add :product_id, :bigint, null: false
      add :sold_quantity, :string, default: "0"
      add :sold_amount, :string, default: "0.00"
      add :ending_quantity, :string, default: "0"
      add :quantity, :string, default: "0"
      add :unit_cost, :string, default: "0.000000"
      add :amount, :string, default: "0.00"
      add :allocated_amount, :string, default: "0.00"
      add :writeoff_amount, :string, default: "0.00"
      add :inventory_account_id, :bigint, default: 0
      add :revenue_account_id, :bigint, default: 0
      add :expense_account_id, :bigint, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:production_receipt_lines, [:doc_id])

    create table(:production_receipt_allocations) do
      add :doc_id, :bigint, null: false
      add :line_no, :integer, default: 0
      add :product_id, :bigint, null: false
      add :account_id, :bigint, null: false
      add :base_amount, :string, default: "0.00"
      add :amount, :string, default: "0.00"

      timestamps(type: :utc_datetime)
    end

    create index(:production_receipt_allocations, [:doc_id])
  end
end

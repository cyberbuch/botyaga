defmodule Botyaga.Repo.Migrations.Phase6Stock do
  use Ecto.Migration

  def change do
    create table(:inventory_lots) do
      add :product_id, :bigint
      add :invoice_id, :bigint
      add :invoice_line_id, :bigint
      add :received_date, :string
      add :quantity, :string
      add :quantity_remaining, :string
      add :unit_cost, :string
      add :location_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:inventory_lots, [:product_id])

    create table(:stock_account_rules) do
      add :company_id, :bigint
      add :kind, :string
      add :inventory_account_id, :bigint
      add :offset_account_id, :bigint
      add :clearing_account_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:stock_account_rules, [:company_id])

    create table(:material_issues) do
      add :company_id, :bigint
      add :number, :string
      add :doc_date, :string
      add :location_id, :bigint
      add :status, :string
      add :notes, :string
      add :journal_entry_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:material_issues, [:company_id])

    create table(:material_issue_lines) do
      add :doc_id, :bigint
      add :product_id, :bigint
      add :quantity, :string
      add :unit_cost, :string
      add :amount, :string
      add :account_id, :bigint
      add :inventory_account_id, :bigint
      add :line_no, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:material_issue_lines, [:doc_id])

    create table(:internal_docs) do
      add :company_id, :bigint
      add :number, :string
      add :doc_date, :string
      add :from_location_id, :bigint
      add :to_location_id, :bigint
      add :status, :string
      add :notes, :string
      add :handed_by, :string
      add :received_by, :string

      timestamps(type: :utc_datetime)
    end

    create index(:internal_docs, [:company_id])

    create table(:internal_doc_lines) do
      add :doc_id, :bigint
      add :line_kind, :string
      add :product_id, :bigint
      add :asset_id, :bigint
      add :quantity, :string
      add :unit_cost, :string
      add :amount, :string
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create index(:internal_doc_lines, [:doc_id])

    create table(:recipes) do
      add :company_id, :bigint
      add :code, :string
      add :name, :string
      add :output_product_id, :bigint
      add :output_quantity, :string
      add :output_unit, :string
      add :notes, :string
      add :is_active, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:recipes, [:company_id])

    create table(:recipe_lines) do
      add :recipe_id, :bigint
      add :product_id, :bigint
      add :quantity, :string
      add :unit, :string
      add :wastage_percent, :string
      add :line_no, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:recipe_lines, [:recipe_id])

    create table(:production_orders) do
      add :company_id, :bigint
      add :number, :string
      add :recipe_id, :bigint
      add :output_product_id, :bigint
      add :quantity, :string
      add :location_id, :bigint
      add :order_date, :string
      add :status, :string
      add :notes, :string
      add :material_cost, :string
      add :journal_entry_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:production_orders, [:company_id])

    create table(:production_order_lines) do
      add :order_id, :bigint
      add :product_id, :bigint
      add :product_name, :string
      add :quantity, :string
      add :unit, :string
      add :unit_cost, :string
      add :amount, :string

      timestamps(type: :utc_datetime)
    end

    create index(:production_order_lines, [:order_id])

    create table(:dividend_distributions) do
      add :company_id, :bigint
      add :year, :integer
      add :total_amount, :string
      add :decision_date, :string
      add :decision_number, :string
      add :status, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:dividend_distributions, [:company_id])

    create table(:dividends) do
      add :company_id, :bigint
      add :distribution_id, :bigint
      add :beneficial_owner_id, :bigint
      add :owner_name, :string
      add :owner_egn, :string
      add :ownership_percentage, :string
      add :gross_amount, :string
      add :tax_rate, :string
      add :tax_amount, :string
      add :net_amount, :string
      add :decision_date, :string
      add :payment_date, :string
      add :is_paid, :integer, default: 0
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:dividends, [:distribution_id])
  end
end

defmodule Botyaga.Repo.Migrations.Phase5BanksAssets do
  use Ecto.Migration

  def change do
    create table(:bank_accounts) do
      add :company_id, :bigint
      add :iban, :string
      add :bic, :string
      add :bank_name, :string
      add :currency, :string
      add :name, :string
      add :account_number, :string
      add :gl_account_id, :bigint
      add :buffer_account_id, :bigint
      add :balance, :string

      timestamps(type: :utc_datetime)
    end

    create index(:bank_accounts, [:company_id])

    create table(:bank_transactions) do
      add :company_id, :bigint
      add :bank_account_id, :bigint
      add :txn_date, :string
      add :amount, :string
      add :currency, :string
      add :counterpart_name, :string
      add :counterpart_iban, :string
      add :description, :string
      add :reference, :string
      add :transaction_type, :string
      add :is_booked, :integer, default: 0
      add :is_allocated, :integer, default: 0
      add :journal_entry_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:bank_transactions, [:company_id])
    create index(:bank_transactions, [:bank_account_id])

    create table(:bank_matching_rules) do
      add :company_id, :bigint
      add :name, :string
      add :keywords, :string
      add :direction, :string
      add :priority, :integer
      add :is_active, :integer, default: 1
      add :account_id, :bigint
      add :counterpart_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:bank_matching_rules, [:company_id])

    create table(:fixed_asset_categories) do
      add :company_id, :bigint
      add :name, :string
      add :cita_category, :string
      add :min_depreciation_rate, :string
      add :max_depreciation_rate, :string
      add :default_method, :string
      add :asset_account_id, :bigint
      add :depreciation_account_id, :bigint
      add :expense_account_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_asset_categories, [:company_id])

    create table(:fixed_assets) do
      add :company_id, :bigint
      add :name, :string
      add :inventory_number, :string
      add :category_id, :bigint
      add :acquisition_date, :string
      add :put_into_service_date, :string
      add :cost, :string
      add :salvage_value, :string
      add :useful_life_months, :string
      add :depreciation_method, :string
      add :accounting_depreciation_rate, :string
      add :tax_depreciation_rate, :string
      add :accumulated_depreciation, :string
      add :tax_accumulated_depreciation, :string
      add :status, :string
      add :serial_number, :string
      add :manufacturer, :string
      add :model, :string
      add :responsible_person, :string
      add :is_conserved, :integer, default: 0
      add :location_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_assets, [:company_id])

    create table(:fixed_asset_events) do
      add :asset_id, :bigint
      add :event_type, :string
      add :event_date, :string
      add :amount, :string
      add :prev_value, :string
      add :location, :string
      add :reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_asset_events, [:asset_id])

    # Курсове на ЕЦБ (импортът идва във фаза 9); трябват за валутните редове при осчетоводяване.
    create table(:exchange_rates) do
      add :code, :string
      add :rate, :string
      add :date, :string

      timestamps(type: :utc_datetime)
    end

    create index(:exchange_rates, [:code, :date])
  end
end

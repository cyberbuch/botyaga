defmodule Botyaga.Repo.Migrations.Phase1Tables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :username, :string
      add :password_hash, :string
      add :role, :string, default: "user"
      add :is_active, :integer, default: 1
      add :is_super_admin, :integer, default: 0
      add :role_id, :integer, default: 0
      add :totp_enabled, :integer, default: 0
      add :totp_secret_b32, :string
      add :totp_pending_b32, :string
      add :session_version, :integer, default: 0
      add :mfa_fails, :integer, default: 0
      add :mfa_lock_until, :bigint, default: 0
      add :created_at, :utc_datetime
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    create table(:roles) do
      add :name, :string, null: false
      add :description, :string
      add :permissions, :text
      add :created_at, :utc_datetime
    end

    create unique_index(:roles, [:name])

    create table(:user_companies) do
      add :user_id, :bigint, null: false
      add :company_id, :bigint, null: false
      add :role_id, :bigint
      add :created_at, :utc_datetime
    end

    create unique_index(:user_companies, [:user_id, :company_id])
    create index(:user_companies, [:company_id])

    create table(:user_recovery_codes) do
      add :user_id, :bigint, null: false
      add :code_hash, :string, null: false
      add :used, :integer, default: 0
    end

    create index(:user_recovery_codes, [:user_id])

    create table(:password_reset_tokens) do
      add :user_id, :bigint, null: false
      add :token_hash, :string, null: false
      add :expires_at, :bigint, null: false
      add :used, :integer, default: 0
    end

    create index(:password_reset_tokens, [:token_hash])
    create index(:password_reset_tokens, [:user_id])

    create table(:settings) do
      add :setting_key, :string, null: false
      add :value, :text
    end

    create unique_index(:settings, [:setting_key])

    create table(:companies) do
      add :name, :string
      add :eik, :string
      add :vat_number, :string
      add :is_vat_registered, :integer, default: 0
      add :vat_period, :string, default: "monthly"
      add :currency, :string, default: "EUR"
      add :address, :string
      add :city, :string
      add :post_code, :string
      add :phone, :string
      add :email, :string
      add :website, :string
      add :mol, :string
      add :manager_eik, :string
      add :accountant_name, :string
      add :accountant_egn, :string
      add :tax_authority, :string
      add :nap_office, :string
      add :iban, :string
      add :bic, :string
      add :inventory_valuation_method, :string, default: "WAC"
      add :fiscal_year_start_month, :integer, default: 1
      add :country, :string, default: "BG"
      add :manager_name, :string
      add :manager_egn, :string
      add :authorized_person_name, :string
      add :authorized_person_egn, :string
      add :vat_branch_number, :string
      add :tax_accounting_basis, :string
      add :tax_entity, :string
      add :software_company_name, :string
      add :software_id, :string
      add :software_version, :string
      add :is_part_of_group, :string
      add :street_name, :string
      add :building_number, :string
      add :address_building, :string
      add :additional_address_detail, :string
      add :address_type, :string
      add :region, :string
      add :settings, :text
      add :created_at, :utc_datetime
    end

    create index(:companies, [:eik])

    create table(:company_locations) do
      add :company_id, :bigint, null: false
      add :name, :string
      add :location_type, :string, default: "OFFICE"
      add :street_name, :string
      add :building_number, :string
      add :city, :string
      add :post_code, :string
      add :region, :string
      add :country, :string, default: "BG"
      add :is_main, :integer, default: 0
    end

    create index(:company_locations, [:company_id])

    create table(:beneficial_owners) do
      add :company_id, :bigint, null: false
      add :first_name_bg, :string
      add :last_name_bg, :string
      add :egn, :string
      add :first_name_latin, :string
      add :last_name_latin, :string
      add :country, :string, default: "BG"
      add :ownership_percentage, :string
    end

    create index(:beneficial_owners, [:company_id])

    create table(:ultimate_parents) do
      add :company_id, :bigint, null: false
      add :name_bg, :string
      add :uic, :string
      add :name_latin, :string
      add :country, :string, default: "BG"
    end

    create index(:ultimate_parents, [:company_id])

    create table(:document_series) do
      add :company_id, :bigint, null: false
      add :name, :string
      add :document_types, :string
      add :pad_width, :integer, default: 10
      add :start_number, :integer, default: 1
      add :next_number, :string
    end

    create index(:document_series, [:company_id])

    create table(:accounts) do
      add :company_id, :bigint
      add :number, :string
      add :name, :string
      add :saft_account_type, :string
      add :analytic_type, :string, default: "none"
      add :is_currency, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:company_id, :number])
    create index(:accounts, [:company_id])

    # Схемата на фактурите е тук, защото серията изчислява следващия номер
    # от изходящите фактури. Ендпойнтите идват във фаза 3.
    create table(:invoices) do
      add :company_id, :bigint
      add :direction, :string
      add :document_type, :string
      add :number, :string
      add :issue_date, :string
      add :due_date, :string
      add :counterpart_id, :bigint
      add :counterpart_name, :string
      add :currency, :string
      add :net_amount, :string
      add :vat_amount, :string
      add :total_amount, :string
      add :status, :string
      add :payment_method, :string
      add :notes, :string
      add :tax_event_date, :string
      add :accounting_month, :string
      add :currency_rate, :string
      add :discount_percent, :string
      add :discount_amount, :string
      add :vat_exemption_reason, :string
      add :original_invoice_id, :bigint
      add :location_id, :bigint
      add :journal_entry_id, :bigint
    end

    create index(:invoices, [:company_id])

    create table(:invoice_lines) do
      add :invoice_id, :bigint
      add :code, :string
      add :description, :string
      add :quantity, :string
      add :unit, :string
      add :unit_price, :string
      add :vat_rate, :string
      add :net_amount, :string
      add :vat_amount, :string
      add :total_amount, :string
      add :product_id, :bigint
    end

    create index(:invoice_lines, [:invoice_id])
  end
end

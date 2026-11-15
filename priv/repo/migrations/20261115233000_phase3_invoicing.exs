defmodule Botyaga.Repo.Migrations.Phase3Invoicing do
  use Ecto.Migration

  def change do
    # invoice_flags е слят във фактурата.
    alter table(:invoices) do
      add :exclude_vat, :integer, default: 0
      add :vat_article, :string
      add :customs_statistical, :string
      add :customs_duty, :string
      add :customs_vat, :string
      add :inserted_at, :utc_datetime
      add :updated_at, :utc_datetime
    end

    alter table(:invoice_lines) do
      add :inserted_at, :utc_datetime
      add :updated_at, :utc_datetime
    end

    create table(:journal_entries) do
      add :company_id, :bigint
      add :entry_date, :string
      add :document_type, :string
      add :document_id, :bigint
      add :document_number, :string
      add :description, :string
      add :vat_type, :string
      add :counterpart_id, :bigint
      add :counterpart_name, :string
      add :document_date, :string
      add :vat_period, :string

      timestamps(type: :utc_datetime)
    end

    create index(:journal_entries, [:company_id])
    create index(:journal_entries, [:document_id, :document_type])

    create table(:journal_lines) do
      add :entry_id, :bigint
      add :account_id, :bigint
      add :account_number, :string
      add :account_name, :string
      add :direction, :string
      add :amount, :string
      add :vat_amount, :string
      add :currency, :string
      add :fx_quantity, :string
      add :fx_rate, :string

      timestamps(type: :utc_datetime)
    end

    create index(:journal_lines, [:entry_id])

    create table(:accounting_periods) do
      add :company_id, :bigint
      add :year, :integer
      add :month, :integer
      add :status, :string
      add :closed_at, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounting_periods, [:company_id, :year, :month])

    create table(:audit_logs) do
      add :company_id, :bigint
      add :user_id, :bigint
      add :user_login, :string
      add :user_name, :string
      add :entity_type, :string
      add :entity_id, :bigint
      add :entity_number, :string
      add :action, :string
      add :summary, :text
      add :old_amount, :string
      add :new_amount, :string
      add :old_data, :text
      add :new_data, :text
      add :created_at, :utc_datetime
    end

    create index(:audit_logs, [:company_id, :entity_type, :entity_id])
  end
end

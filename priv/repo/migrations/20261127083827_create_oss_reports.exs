defmodule Botyaga.Repo.Migrations.CreateOssReports do
  use Ecto.Migration

  def change do
    create table(:oss_reports) do
      add :company_id, :bigint, null: false
      add :number, :string, null: false, default: ""
      add :doc_date, :string, null: false, default: ""
      add :month, :string, null: false, default: ""
      add :status, :string, null: false, default: "draft"
      add :correction_of_id, :bigint, null: false, default: 0
      add :correction_quarter, :string, null: false, default: ""
      add :notes, :string, null: false, default: ""
      add :journal_entry_id, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:oss_reports, [:company_id])

    create table(:oss_report_lines) do
      add :report_id, references(:oss_reports, on_delete: :delete_all), null: false
      add :account, :string, null: false, default: "702"
      add :country, :string, null: false, default: ""
      add :supply_kind, :string, null: false, default: "goods"
      add :rate_kind, :string, null: false, default: "standard"
      add :rate, :string, null: false, default: "0"
      add :gross, :string, null: false, default: "0"
      add :currency, :string, null: false, default: "EUR"
      add :fx, :string, null: false, default: "1"
      add :gross_eur, :string, null: false, default: "0"
      add :base_eur, :string, null: false, default: "0"
      add :vat_eur, :string, null: false, default: "0"
      add :quantity, :string, null: false, default: ""
      add :order_no, :string, null: false, default: ""
      add :description, :string, null: false, default: ""
      add :delivery_date, :string, null: false, default: ""
    end

    create index(:oss_report_lines, [:report_id])

    create table(:oss_declarations) do
      add :company_id, :bigint, null: false
      add :year, :integer, null: false
      add :quarter, :integer, null: false
      add :status, :string, null: false, default: "draft"
      add :submitted_at, :string, null: false, default: ""
      add :submission_no, :string, null: false, default: ""
      add :frozen, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:oss_declarations, [:company_id, :year, :quarter])
  end
end

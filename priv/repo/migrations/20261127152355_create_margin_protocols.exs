defmodule Botyaga.Repo.Migrations.CreateMarginProtocols do
  use Ecto.Migration

  def change do
    create table(:margin_protocols) do
      add :company_id, :bigint, null: false
      add :month, :string, null: false
      add :number, :string, null: false, default: ""
      add :status, :string, null: false, default: "draft"
      add :journal_entry_id, :bigint, null: false, default: 0
      add :total_base, :string, null: false, default: "0.00"
      add :total_vat, :string, null: false, default: "0.00"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:margin_protocols, [:company_id, :month])

    create table(:margin_protocol_lines) do
      add :protocol_id, references(:margin_protocols, on_delete: :delete_all), null: false
      add :product_id, :bigint, null: false
      add :sale_invoice_id, :bigint, null: false, default: 0
      add :purchase_price, :string, null: false, default: "0.00"
      add :sale_price, :string, null: false, default: "0.00"
      add :margin, :string, null: false, default: "0.00"
      add :base, :string, null: false, default: "0.00"
      add :vat, :string, null: false, default: "0.00"
      add :export, :integer, null: false, default: 0
    end

    create index(:margin_protocol_lines, [:protocol_id])
  end
end

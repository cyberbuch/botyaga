defmodule Botyaga.Repo.Migrations.AddMarginToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :is_margin, :integer, null: false, default: 0
      add :margin_export, :integer, null: false, default: 0
    end
  end
end

defmodule Botyaga.Repo.Migrations.AddIsOssToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :is_oss, :integer, null: false, default: 0
    end
  end
end

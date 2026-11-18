defmodule Botyaga.Repo.Migrations.AddBankAccountToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :bank_account_id, :bigint, default: 0, null: false
    end
  end
end

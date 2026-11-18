defmodule Botyaga.Repo.Migrations.AddStatementFormatToBankAccounts do
  use Ecto.Migration

  def change do
    alter table(:bank_accounts) do
      add :statement_format, :string, default: "", null: false
    end
  end
end

defmodule Botyaga.Repo.Migrations.Phase8Saft do
  use Ecto.Migration

  def change do
    create table(:saft_account_mappings) do
      add :company_id, :bigint
      add :kind, :string
      add :type_code, :string
      add :debit_account, :string
      add :credit_account, :string
      add :debit_analytical, :string
      add :credit_analytical, :string
      add :description, :string
      add :is_active, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:saft_account_mappings, [:company_id, :kind])
  end
end

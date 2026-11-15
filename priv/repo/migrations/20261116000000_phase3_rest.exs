defmodule Botyaga.Repo.Migrations.Phase3Rest do
  use Ecto.Migration

  def change do
    create table(:opening_balances) do
      add :company_id, :bigint
      add :fiscal_year, :integer
      add :account_id, :bigint
      add :debit, :string
      add :credit, :string
      add :counterpart_id, :bigint
      add :product_id, :bigint
      add :quantity, :string
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create index(:opening_balances, [:company_id, :fiscal_year])
  end
end

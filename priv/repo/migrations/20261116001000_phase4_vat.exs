defmodule Botyaga.Repo.Migrations.Phase4Vat do
  use Ecto.Migration

  def change do
    create table(:vat_manual) do
      add :company_id, :bigint
      add :period, :string
      add :cell_33, :string
      add :cell_70, :string
      add :cell_71, :string
      add :cell_80, :string
      add :cell_81, :string
      add :cell_82, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vat_manual, [:company_id, :period])
  end
end

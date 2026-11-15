defmodule Botyaga.Repo.Migrations.Phase9Pnmap do
  use Ecto.Migration

  def change do
    create table(:product_name_mappings) do
      add :company_id, :bigint
      add :counterpart_id, :bigint
      add :scanned_name, :string
      add :product_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:product_name_mappings, [:company_id, :counterpart_id])
  end
end

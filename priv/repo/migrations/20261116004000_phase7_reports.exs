defmodule Botyaga.Repo.Migrations.Phase7Reports do
  use Ecto.Migration

  def change do
    create table(:fs_line_formulas) do
      add :company_id, :bigint
      add :statement, :string
      add :line_code, :string
      add :formula, :string

      timestamps(type: :utc_datetime)
    end

    create index(:fs_line_formulas, [:company_id, :statement])
  end
end

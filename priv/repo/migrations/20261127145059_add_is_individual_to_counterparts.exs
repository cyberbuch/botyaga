defmodule Botyaga.Repo.Migrations.AddIsIndividualToCounterparts do
  use Ecto.Migration

  def change do
    alter table(:counterparts) do
      add :is_individual, :integer, null: false, default: 0
    end
  end
end

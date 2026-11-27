defmodule Botyaga.Repo.Migrations.AddOssEnabledToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :oss_enabled, :integer, null: false, default: 0
    end
  end
end

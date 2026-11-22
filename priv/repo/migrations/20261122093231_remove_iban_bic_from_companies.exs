defmodule Botyaga.Repo.Migrations.RemoveIbanBicFromCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      remove :iban
      remove :bic
    end
  end
end

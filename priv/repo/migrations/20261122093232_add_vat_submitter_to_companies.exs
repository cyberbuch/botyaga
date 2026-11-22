defmodule Botyaga.Repo.Migrations.AddVatSubmitterToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :vat_submitter, :string, default: "accountant", null: false
    end
  end
end

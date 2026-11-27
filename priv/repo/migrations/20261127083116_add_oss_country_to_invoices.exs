defmodule Botyaga.Repo.Migrations.AddOssCountryToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :oss_country, :string, null: false, default: ""
    end
  end
end

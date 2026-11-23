defmodule Botyaga.Repo.Migrations.AddVatGoodsDefaultsToCompanies do
  use Ecto.Migration

  def change do
    alter table(:companies) do
      add :vat_purchase_goods, :string, default: "stock", null: false
      add :vat_sales_goods, :string, default: "stock", null: false
    end
  end
end

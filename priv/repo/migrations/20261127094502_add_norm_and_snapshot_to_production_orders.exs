defmodule Botyaga.Repo.Migrations.AddNormAndSnapshotToProductionOrders do
  use Ecto.Migration

  def change do
    alter table(:production_orders) do
      add :recipe_snapshot, :text
    end

    alter table(:production_order_lines) do
      add :norm_quantity, :string, null: false, default: "0"
    end
  end
end

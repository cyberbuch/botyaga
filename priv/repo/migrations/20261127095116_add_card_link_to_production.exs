defmodule Botyaga.Repo.Migrations.AddCardLinkToProduction do
  use Ecto.Migration

  def change do
    alter table(:production_cards) do
      add :kind, :string, null: false, default: "actual"
    end

    alter table(:production_orders) do
      add :card_id, :bigint, null: false, default: 0
    end

    create index(:production_orders, [:card_id])
  end
end

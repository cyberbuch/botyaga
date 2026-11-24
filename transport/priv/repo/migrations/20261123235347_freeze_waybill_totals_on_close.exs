defmodule Transport.Repo.Migrations.FreezeWaybillTotalsOnClose do
  use Ecto.Migration

  # Приключеният пътен лист пази норматива и изчисленията към момента: промяна на
  # норматива на автомобила по-късно не бива да пренаписва вече подписан документ.
  def change do
    alter table(:waybills) do
      add :norm, :string, default: ""
      add :winter_surcharge, :integer, default: 0
      add :total_km, :string, default: ""
      add :total_refuel, :string, default: ""
      add :norm_consumption, :string, default: ""
    end
  end
end

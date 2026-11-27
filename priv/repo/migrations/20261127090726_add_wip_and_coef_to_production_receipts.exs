defmodule Botyaga.Repo.Migrations.AddWipAndCoefToProductionReceipts do
  use Ecto.Migration

  def change do
    alter table(:production_receipts) do
      add :wip_end_mode, :string, null: false, default: "amount"
      add :wip_end_value, :string, null: false, default: "0"
    end

    alter table(:production_receipt_lines) do
      add :coefficient, :string, null: false, default: "1"
      add :manual_amount, :string, null: false, default: ""
    end
  end
end

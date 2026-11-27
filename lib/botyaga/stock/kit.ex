defmodule Botyaga.Stock.Kit do
  @moduledoc "Комплектоване: пакет от стоки (304) или продукция (303) по рецепта, без производствени разходи."
  use Ecto.Schema

  schema "kits" do
    field :company_id, :integer
    field :number, :string, default: ""
    field :doc_date, :string, default: ""
    field :status, :string, default: "draft"
    field :kind, :string, default: "kit_goods"
    field :output_product_id, :integer, default: 0
    field :quantity, :string, default: "0"
    field :location_id, :integer, default: 0
    field :recipe_id, :integer, default: 0
    field :cost, :string, default: "0.00"
    field :journal_entry_id, :integer, default: 0
    field :notes, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

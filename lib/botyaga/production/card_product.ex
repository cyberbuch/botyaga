defmodule Botyaga.Production.CardProduct do
  @moduledoc "Продукт в месечната карта: количество, коефициент или ръчна сума."
  use Ecto.Schema

  schema "production_card_products" do
    field :card_id, :integer
    field :product_id, :integer
    field :quantity, :string, default: "0"
    field :coefficient, :string, default: "1"
    field :manual_amount, :string, default: ""
    field :cost, :string, default: "0"
    field :inventory_account_id, :integer, default: 0
  end
end

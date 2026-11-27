defmodule Botyaga.Stock.KitLine do
  @moduledoc "Съставка на комплект: артикул и количество."
  use Ecto.Schema

  schema "kit_lines" do
    field :kit_id, :integer
    field :product_id, :integer
    field :quantity, :string, default: "0"
  end
end

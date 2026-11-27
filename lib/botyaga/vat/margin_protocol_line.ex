defmodule Botyaga.Vat.MarginProtocolLine do
  @moduledoc "Ред в протокола за маржа: стока, покупна/продажна цена, марж, основа, ДДС."
  use Ecto.Schema

  schema "margin_protocol_lines" do
    field :protocol_id, :integer
    field :product_id, :integer
    field :sale_invoice_id, :integer, default: 0
    field :purchase_price, :string, default: "0.00"
    field :sale_price, :string, default: "0.00"
    field :margin, :string, default: "0.00"
    field :base, :string, default: "0.00"
    field :vat, :string, default: "0.00"
    field :export, :integer, default: 0
  end
end

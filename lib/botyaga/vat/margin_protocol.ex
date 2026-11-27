defmodule Botyaga.Vat.MarginProtocol do
  @moduledoc "Месечен протокол за маржа по чл.90 ППЗДС (стоки втора употреба)."
  use Ecto.Schema

  schema "margin_protocols" do
    field :company_id, :integer
    field :month, :string
    field :number, :string, default: ""
    field :status, :string, default: "draft"
    field :journal_entry_id, :integer, default: 0
    field :total_base, :string, default: "0.00"
    field :total_vat, :string, default: "0.00"
    timestamps(type: :utc_datetime)
  end
end

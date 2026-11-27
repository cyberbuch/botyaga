defmodule Botyaga.Oss.Rate do
  @moduledoc "OSS ДДС ставка по държава с аналитична сметка и начална дата (история)."
  use Ecto.Schema

  schema "oss_vat_rates" do
    field :company_id, :integer
    field :country, :string
    field :account_id, :integer, default: 0
    field :rate, :string, default: "0"
    field :rate_kind, :string, default: "standard"
    field :supply_kind, :string, default: "goods"
    field :valid_from, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

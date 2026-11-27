defmodule Botyaga.Vat.Operation do
  @moduledoc "Междинна ДДС операция на фирма: категория, код за колоната, допълнителен код, ставка, сметки, протокол."

  use Ecto.Schema

  schema "vat_operations" do
    field :company_id, :integer
    field :name, :string
    field :category, :string
    field :code, :integer, default: 0
    field :additional, :integer, default: 0
    field :rate, :string, default: "20"
    field :counterpart_account_id, :integer, default: 0
    field :vat_account_id, :integer, default: 0
    field :protocol, :string, default: ""
    field :oss_country, :string, default: ""
    field :oss_rate_kind, :string, default: ""
    field :oss_supply_kind, :string, default: ""
    timestamps(type: :utc_datetime)
  end
end

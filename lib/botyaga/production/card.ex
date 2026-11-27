defmodule Botyaga.Production.Card do
  @moduledoc "Месечна производствена карта (фактическо производство) — ръчен подход."
  use Ecto.Schema

  schema "production_cards" do
    field :company_id, :integer
    field :number, :string, default: ""
    field :month, :string, default: ""
    field :status, :string, default: "draft"
    field :materials_account_id, :integer, default: 0
    field :production_account_id, :integer, default: 0
    field :direct_accounts, :string
    field :common_accounts, :string
    field :common_share_percent, :string, default: "100"
    field :wip_end_mode, :string, default: "amount"
    field :wip_end_value, :string, default: "0"
    field :journal_entry_id, :integer, default: 0
    field :notes, :string, default: ""
    field :kind, :string, default: "actual"
    timestamps(type: :utc_datetime)
  end
end

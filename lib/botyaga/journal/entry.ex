defmodule Botyaga.Journal.Entry do
  use Ecto.Schema

  schema "journal_entries" do
    field :company_id, :id
    field :entry_date, :string
    field :document_type, :string
    field :document_id, :integer, default: 0
    field :document_number, :string
    field :description, :string
    field :vat_type, :string
    field :counterpart_id, :integer, default: 0
    field :counterpart_name, :string
    field :document_date, :string
    field :vat_period, :string

    timestamps(type: :utc_datetime)
  end
end

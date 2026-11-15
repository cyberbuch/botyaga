defmodule Botyaga.Stock.MaterialIssue do
  use Ecto.Schema

  schema "material_issues" do
    field :company_id, :id
    field :number, :string
    field :doc_date, :string
    field :location_id, :integer, default: 0
    field :status, :string
    field :notes, :string
    field :journal_entry_id, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end

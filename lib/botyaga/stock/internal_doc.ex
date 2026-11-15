defmodule Botyaga.Stock.InternalDoc do
  use Ecto.Schema

  schema "internal_docs" do
    field :company_id, :id
    field :number, :string
    field :doc_date, :string
    field :from_location_id, :integer, default: 0
    field :to_location_id, :integer, default: 0
    field :status, :string
    field :notes, :string
    field :handed_by, :string
    field :received_by, :string

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Companies.Series do
  use Ecto.Schema

  schema "document_series" do
    field :company_id, :id
    field :name, :string
    field :document_types, :string
    field :pad_width, :integer, default: 10
    field :start_number, :integer, default: 1
    field :next_number, :string
  end
end

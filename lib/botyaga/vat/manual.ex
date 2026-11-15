defmodule Botyaga.Vat.Manual do
  use Ecto.Schema

  schema "vat_manual" do
    field :company_id, :id
    field :period, :string
    field :cell_33, :string
    field :cell_70, :string
    field :cell_71, :string
    field :cell_80, :string
    field :cell_81, :string
    field :cell_82, :string

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Pnmap.Mapping do
  use Ecto.Schema

  schema "product_name_mappings" do
    field :company_id, :id
    field :counterpart_id, :integer
    field :scanned_name, :string
    field :product_id, :integer

    timestamps(type: :utc_datetime)
  end
end

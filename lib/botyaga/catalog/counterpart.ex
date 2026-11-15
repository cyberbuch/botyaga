defmodule Botyaga.Catalog.Counterpart do
  use Ecto.Schema

  schema "counterparts" do
    field :company_id, :id
    field :name, :string
    field :counterpart_type, :string, default: "both"
    field :eik, :string
    field :vat_number, :string
    field :address, :string
    field :city, :string
    field :post_code, :string
    field :country, :string, default: "BG"
    field :contact_person, :string
    field :vies_address, :string
    field :street_name, :string
    field :building_number, :string
    field :address_building, :string
    field :additional_address_detail, :string
    field :address_type, :string
    field :region, :string
    field :email, :string
    field :phone, :string

    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Companies.Location do
  use Ecto.Schema

  schema "company_locations" do
    field :company_id, :id
    field :name, :string
    field :location_type, :string, default: "OFFICE"
    field :street_name, :string
    field :building_number, :string
    field :city, :string
    field :post_code, :string
    field :region, :string
    field :country, :string, default: "BG"
    field :is_main, :integer, default: 0
  end
end

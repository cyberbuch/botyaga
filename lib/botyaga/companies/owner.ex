defmodule Botyaga.Companies.Owner do
  use Ecto.Schema

  schema "beneficial_owners" do
    field :company_id, :id
    field :first_name_bg, :string
    field :last_name_bg, :string
    field :egn, :string
    field :first_name_latin, :string
    field :last_name_latin, :string
    field :country, :string, default: "BG"
    field :ownership_percentage, :string
  end
end

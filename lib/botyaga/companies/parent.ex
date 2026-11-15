defmodule Botyaga.Companies.Parent do
  use Ecto.Schema

  schema "ultimate_parents" do
    field :company_id, :id
    field :name_bg, :string
    field :uic, :string
    field :name_latin, :string
    field :country, :string, default: "BG"
  end
end

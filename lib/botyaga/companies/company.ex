defmodule Botyaga.Companies.Company do
  use Ecto.Schema

  schema "companies" do
    field :name, :string
    field :eik, :string
    field :vat_number, :string
    field :is_vat_registered, :integer, default: 0
    field :vat_period, :string, default: "monthly"
    field :currency, :string, default: "EUR"
    field :address, :string
    field :city, :string
    field :post_code, :string
    field :phone, :string
    field :email, :string
    field :website, :string
    field :mol, :string
    field :manager_eik, :string
    field :accountant_name, :string
    field :accountant_egn, :string
    field :tax_authority, :string
    field :nap_office, :string
    field :iban, :string
    field :bic, :string
    field :inventory_valuation_method, :string, default: "WAC"
    field :fiscal_year_start_month, :integer, default: 1
    field :country, :string, default: "BG"
    field :manager_name, :string
    field :manager_egn, :string
    field :authorized_person_name, :string
    field :authorized_person_egn, :string
    field :vat_branch_number, :string
    field :tax_accounting_basis, :string
    field :tax_entity, :string
    field :software_company_name, :string
    field :software_id, :string
    field :software_version, :string
    field :is_part_of_group, :string
    field :street_name, :string
    field :building_number, :string
    field :address_building, :string
    field :additional_address_detail, :string
    field :address_type, :string
    field :region, :string
    field :settings, :string
    field :created_at, :utc_datetime
  end
end

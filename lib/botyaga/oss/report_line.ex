defmodule Botyaga.Oss.ReportLine do
  @moduledoc "Ред в OSS отчет: държава, вид доставка/ставка, сума с ДДС и основа/ДДС в EUR."
  use Ecto.Schema

  schema "oss_report_lines" do
    field :report_id, :integer
    field :account, :string, default: "702"
    field :country, :string, default: ""
    field :supply_kind, :string, default: "goods"
    field :rate_kind, :string, default: "standard"
    field :rate, :string, default: "0"
    field :gross, :string, default: "0"
    field :currency, :string, default: "EUR"
    field :fx, :string, default: "1"
    field :gross_eur, :string, default: "0"
    field :base_eur, :string, default: "0"
    field :vat_eur, :string, default: "0"
    field :quantity, :string, default: ""
    field :order_no, :string, default: ""
    field :description, :string, default: ""
    field :delivery_date, :string, default: ""
  end
end

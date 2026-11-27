defmodule Botyaga.Invoicing.Invoice do
  use Ecto.Schema

  schema "invoices" do
    field :company_id, :id
    field :direction, :string
    field :document_type, :string
    field :number, :string
    field :issue_date, :string
    field :due_date, :string
    field :counterpart_id, :id
    field :counterpart_name, :string
    field :currency, :string
    field :net_amount, :string
    field :vat_amount, :string
    field :total_amount, :string
    field :status, :string
    field :payment_method, :string
    field :notes, :string
    field :tax_event_date, :string
    field :accounting_month, :string
    field :currency_rate, :string
    field :discount_percent, :string
    field :discount_amount, :string
    field :vat_exemption_reason, :string
    field :original_invoice_id, :id
    field :location_id, :id
    field :bank_account_id, :id, default: 0
    field :journal_entry_id, :id
    field :exclude_vat, :integer, default: 0
    field :is_oss, :integer, default: 0
    field :oss_country, :string, default: ""
    field :vat_article, :string
    field :customs_statistical, :string
    field :customs_duty, :string
    field :customs_vat, :string

    timestamps(type: :utc_datetime)
  end
end

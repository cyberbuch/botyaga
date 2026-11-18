defmodule Botyaga.Printing.Load do
  @moduledoc "Фактура, редове, фирма и контрагент за печат и UBL. Порт на `print_load.rs`."

  alias Botyaga.{Banking, Companies, Invoicing, Repo}
  alias Botyaga.Catalog.Counterpart
  alias Botyaga.Invoicing.Invoice
  alias BotyagaWeb.Render

  def load(company_id, id) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id) do
      value = Invoicing.Read.value(inv, true)
      firm_id = if inv.company_id > 0, do: inv.company_id, else: company_id
      {orig_no, orig_date} = original(company_id, inv.original_invoice_id)

      {:ok,
       %{
         inv: value,
         lines: Map.get(value, :lines, []),
         company: company_json(firm_id),
         counterpart: counterpart_json(inv.counterpart_id, firm_id),
         bank: bank_json(inv.bank_account_id, firm_id),
         original_number: orig_no,
         original_date: orig_date
       }}
    end
  end

  defp company_json(firm_id) do
    case Companies.get_company(firm_id) do
      nil -> %{}
      company -> Render.company(company)
    end
  end

  defp counterpart_json(id, firm_id) when id > 0 do
    case Repo.get_by(Counterpart, id: id, company_id: firm_id) do
      nil -> %{}
      counterpart -> Render.counterpart(counterpart)
    end
  end

  defp counterpart_json(_id, _firm_id), do: %{}

  defp bank_json(id, firm_id) when id > 0 do
    case Repo.get_by(Banking.Account, id: id, company_id: firm_id) do
      nil ->
        %{}

      account ->
        %{
          name: String.trim(account.name || ""),
          iban: String.trim(account.iban || ""),
          bic: String.trim(account.bic || "")
        }
    end
  end

  defp bank_json(_id, _firm_id), do: %{}

  defp original(company_id, id) when id > 0 do
    case Repo.get_by(Invoice, id: id, company_id: company_id) do
      nil -> {"", ""}
      inv -> {inv.number || "", inv.issue_date || ""}
    end
  end

  defp original(_company_id, _id), do: {"", ""}

  def party(v) do
    %{
      name: field(v, :name),
      eik: field(v, :eik),
      vat: field(v, :vat_number),
      address: field(v, :address),
      city: field(v, :city),
      post: field(v, :post_code),
      country: field(v, :country),
      email: field(v, :email),
      phone: field(v, :phone),
      mol: field(v, :mol),
      contact: field(v, :contact_person),
      iban: field(v, :iban),
      bic: field(v, :bic)
    }
  end

  def field(v, key) do
    case Map.get(v, key) do
      nil -> ""
      value -> value |> to_string() |> String.trim()
    end
  end
end

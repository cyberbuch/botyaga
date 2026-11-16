defmodule Botyaga.Invoicing.Read do
  @moduledoc "Четене на фактури: списък, детайл и JSON форматът на ytbuch."

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Repo}
  alias Botyaga.Invoicing.{Head, Invoice}
  alias Botyaga.Journal

  def list(company_id) do
    invoices =
      Repo.all(from(i in Invoice, where: i.company_id == ^company_id, order_by: [asc: i.id]))

    stamps = Audit.stamps_for(company_id, "invoice")

    Enum.map(invoices, fn inv ->
      inv |> value(false) |> Audit.attach_stamp(Map.get(stamps, inv.id))
    end)
  end

  def detail(company_id, _sub, id) do
    with {:ok, inv} <- Botyaga.Invoicing.fetch(company_id, id) do
      value = value(inv, true)
      value = maybe_put_counterpart(value, inv.counterpart_id, company_id)
      value = maybe_put_company(value, company_id)
      value = Audit.attach_stamp(value, Map.get(Audit.stamps_for(company_id, "invoice"), inv.id))
      value = put_payment(value, company_id, inv.id)
      {:ok, Map.put(value, :audit_history, Audit.history_for(company_id, "invoice", inv.id))}
    end
  end

  defp put_payment(value, company_id, invoice_id) do
    case Botyaga.Invoicing.Payment.fetch_payment(company_id, invoice_id) do
      {:ok, entry} -> value |> Map.put(:is_paid, true) |> Map.put(:payment_entry_id, entry.id)
      {:error, _} -> Map.put(value, :is_paid, false)
    end
  end

  @doc "JSON на фактурата — същите ключове като ytbuch."
  def value(inv, with_lines) do
    inv = fill(inv)
    journal_entry_id = posted_entry(inv)

    base = %{
      id: inv.id,
      company_id: inv.company_id,
      direction: inv.direction,
      document_type: inv.document_type,
      number: inv.number,
      issue_date: inv.issue_date,
      due_date: inv.due_date,
      tax_event_date: inv.tax_event_date,
      accounting_month: inv.accounting_month,
      counterpart_id: inv.counterpart_id,
      counterpart_name: inv.counterpart_name,
      currency: inv.currency,
      currency_rate: inv.currency_rate,
      net_amount: inv.net_amount,
      vat_amount: inv.vat_amount,
      total_amount: inv.total_amount,
      status: inv.status,
      payment_method: inv.payment_method,
      notes: inv.notes,
      discount_percent: inv.discount_percent,
      discount_amount: inv.discount_amount,
      vat_exemption_reason: inv.vat_exemption_reason,
      location_id: inv.location_id,
      exclude_vat: inv.exclude_vat,
      vat_article: inv.vat_article,
      customs_statistical: inv.customs_statistical,
      customs_duty: inv.customs_duty,
      customs_vat: inv.customs_vat
    }

    base =
      if inv.original_invoice_id > 0,
        do: Map.put(base, :original_invoice_id, inv.original_invoice_id),
        else: base

    base =
      if journal_entry_id > 0, do: Map.put(base, :journal_entry_id, journal_entry_id), else: base

    if with_lines do
      Map.put(base, :lines, Enum.map(lines_of(inv.id), &line_json/1))
    else
      base
    end
  end

  defp line_json(line) do
    base = %{
      id: line.id,
      code: line.code,
      description: line.description,
      quantity: line.quantity,
      unit: line.unit,
      unit_price: line.unit_price,
      vat_rate: line.vat_rate,
      net_amount: line.net_amount,
      vat_amount: line.vat_amount,
      total_amount: line.total_amount
    }

    if line.product_id > 0, do: Map.put(base, :product_id, line.product_id), else: base
  end

  def head_of(inv) do
    %{
      direction: inv.direction,
      document_type: inv.document_type,
      number: inv.number,
      issue_date: inv.issue_date,
      due_date: inv.due_date,
      tax_event_date: inv.tax_event_date,
      accounting_month: inv.accounting_month,
      counterpart_id: inv.counterpart_id,
      currency: inv.currency,
      currency_rate: inv.currency_rate,
      payment_method: inv.payment_method,
      notes: inv.notes,
      discount_percent: inv.discount_percent,
      discount_amount: inv.discount_amount,
      vat_exemption_reason: inv.vat_exemption_reason,
      original_invoice_id: inv.original_invoice_id,
      location_id: inv.location_id,
      exclude_vat: inv.exclude_vat,
      vat_article: inv.vat_article,
      customs_statistical: inv.customs_statistical,
      customs_duty: inv.customs_duty,
      customs_vat: inv.customs_vat
    }
  end

  defp fill(inv) do
    %{
      inv
      | tax_event_date: default(inv.tax_event_date, inv.issue_date),
        accounting_month: default(inv.accounting_month, Head.month_of(inv.issue_date || "", "")),
        currency_rate: default(inv.currency_rate, "1"),
        discount_percent: default(inv.discount_percent, "0"),
        discount_amount: default(inv.discount_amount, "0")
    }
  end

  defp lines_of(invoice_id), do: Botyaga.Invoicing.lines_of(invoice_id)

  defp posted_entry(inv) do
    if inv.journal_entry_id > 0 or inv.status != "posted" do
      inv.journal_entry_id
    else
      Repo.one(
        from(e in Journal.Entry,
          where: e.document_id == ^inv.id and e.document_type == ^inv.document_type,
          order_by: [desc: e.id],
          select: e.id,
          limit: 1
        )
      ) || 0
    end
  end

  defp maybe_put_counterpart(value, counterpart_id, company_id) when counterpart_id > 0 do
    case Repo.get_by(Catalog.Counterpart, id: counterpart_id, company_id: company_id) do
      nil -> value
      counterpart -> Map.put(value, :counterpart, BotyagaWeb.Render.counterpart(counterpart))
    end
  end

  defp maybe_put_counterpart(value, _counterpart_id, _company_id), do: value

  defp maybe_put_company(value, company_id) do
    case Companies.get_company(company_id) do
      nil -> value
      company -> Map.put(value, :company, BotyagaWeb.Render.company(company))
    end
  end

  defp default(value, fallback) do
    if is_nil(value) or String.trim(value) == "", do: fallback, else: value
  end
end

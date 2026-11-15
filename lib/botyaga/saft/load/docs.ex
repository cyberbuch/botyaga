defmodule Botyaga.Saft.Load.Docs do
  @moduledoc """
  Документите за SAF-T снимката: фактури, банкови движения, ДМА, изписвания,
  производство и вътрешни протоколи. Порт на документната част от `saft_load.rs`.
  """

  import Ecto.Query

  alias Botyaga.Repo
  alias Botyaga.Saft.Xml
  alias Botyaga.Catalog.Account, as: CatAccount
  alias Botyaga.Invoicing.{Invoice, InvoiceLine}
  alias Botyaga.Banking.{Account, Transaction}
  alias Botyaga.Assets.Asset
  alias Botyaga.Stock.{MaterialIssue, MaterialIssueLine, InternalDoc, InternalDocLine}
  alias Botyaga.Production.{Order, OrderLine}

  def load(company_id, snap) do
    invoices = invoices_of(company_id)
    inv_ids = Enum.map(invoices, & &1.id)
    mat_issues = mat_issues_of(company_id)
    prod_orders = prod_orders_of(company_id)
    idocs = idocs_of(company_id)

    Map.merge(snap, %{
      invoices: invoices,
      inv_lines: inv_lines_of(inv_ids),
      banks: banks_of(company_id),
      assets: assets_of(company_id),
      mat_issues: mat_issues,
      mat_lines: mat_lines_of(Enum.map(mat_issues, & &1.id)),
      prod_orders: prod_orders,
      prod_lines: prod_lines_of(Enum.map(prod_orders, & &1.id)),
      idocs: idocs,
      idoc_lines: idoc_lines_of(Enum.map(idocs, & &1.id))
    })
  end

  defp invoices_of(company_id) do
    Repo.all(from(i in Invoice, where: i.company_id == ^company_id, order_by: [asc: i.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        direction: &1.direction || "",
        document_type: &1.document_type || "",
        number: &1.number || "",
        issue_date: &1.issue_date || "",
        counterpart_id: &1.counterpart_id || 0,
        currency: &1.currency || "",
        net: Xml.money_of(&1.net_amount),
        vat: Xml.money_of(&1.vat_amount),
        total: Xml.money_of(&1.total_amount),
        accounting_month: &1.accounting_month || "",
        tax_date: &1.tax_event_date || "",
        reason: &1.vat_exemption_reason || "",
        journal_entry_id: &1.journal_entry_id || 0
      }
    )
  end

  defp inv_lines_of([]), do: %{}

  defp inv_lines_of(ids) do
    Repo.all(from(l in InvoiceLine, where: l.invoice_id in ^ids, order_by: [asc: l.id]))
    |> Enum.map(
      &%{
        invoice_id: &1.invoice_id,
        code: &1.code || "",
        description: &1.description || "",
        quantity: &1.quantity || "",
        unit: &1.unit || "",
        price: Xml.money_of(&1.unit_price),
        rate: Xml.money_of(&1.vat_rate),
        net: Xml.money_of(&1.net_amount),
        vat: Xml.money_of(&1.vat_amount),
        product_id: &1.product_id || 0
      }
    )
    |> Enum.group_by(& &1.invoice_id)
  end

  defp banks_of(company_id) do
    gl_of =
      Repo.all(from(b in Account, where: b.company_id == ^company_id))
      |> Enum.reduce(%{}, fn b, acc ->
        num = account_number(b.gl_account_id)
        if Xml.nra_ok(num), do: Map.put(acc, b.id, String.trim(num)), else: acc
      end)

    Repo.all(from(t in Transaction, where: t.company_id == ^company_id, order_by: [asc: t.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        date: &1.txn_date || "",
        amount: Xml.money_of(&1.amount),
        currency: &1.currency || "",
        name: &1.counterpart_name || "",
        description: &1.description || "",
        reference: &1.reference || "",
        kind: &1.transaction_type || "",
        booked: &1.is_booked == 1,
        journal_id: &1.journal_entry_id || 0,
        gl: Map.get(gl_of, &1.bank_account_id, "")
      }
    )
  end

  defp account_number(id) when id > 0 do
    case Repo.get(CatAccount, id) do
      nil -> ""
      a -> a.number || ""
    end
  end

  defp account_number(_), do: ""

  defp assets_of(company_id) do
    Repo.all(from(a in Asset, where: a.company_id == ^company_id, order_by: [asc: a.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        name: &1.name || "",
        inventory: &1.inventory_number || "",
        category_id: &1.category_id || 0,
        acquired: &1.acquisition_date || "",
        startup: &1.put_into_service_date || "",
        cost: Xml.money_of(&1.cost),
        life: &1.useful_life_months || "",
        method: &1.depreciation_method || "",
        rate: &1.accounting_depreciation_rate || "",
        acc: Xml.money_of(&1.accumulated_depreciation),
        tax_acc: Xml.money_of(&1.tax_accumulated_depreciation),
        tax_rate: &1.tax_depreciation_rate || ""
      }
    )
  end

  defp mat_issues_of(company_id) do
    Repo.all(from(d in MaterialIssue, where: d.company_id == ^company_id, order_by: [asc: d.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        number: &1.number || "",
        date: &1.doc_date || "",
        status: &1.status || "",
        journal_id: &1.journal_entry_id || 0
      }
    )
  end

  defp mat_lines_of([]), do: %{}

  defp mat_lines_of(ids) do
    Repo.all(from(l in MaterialIssueLine, where: l.doc_id in ^ids, order_by: [asc: l.id]))
    |> Enum.map(
      &%{
        doc_id: &1.doc_id,
        product_id: &1.product_id || 0,
        quantity: &1.quantity || "",
        amount: Xml.money_of(&1.amount),
        inventory_account_id: &1.inventory_account_id || 0,
        line_no: &1.line_no || 0
      }
    )
    |> Enum.group_by(& &1.doc_id)
  end

  defp prod_orders_of(company_id) do
    Repo.all(from(o in Order, where: o.company_id == ^company_id, order_by: [asc: o.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        number: &1.number || "",
        output_product_id: &1.output_product_id || 0,
        quantity: &1.quantity || "",
        date: &1.order_date || "",
        status: &1.status || "",
        journal_id: &1.journal_entry_id || 0,
        cost: Xml.money_of(&1.material_cost)
      }
    )
  end

  defp prod_lines_of([]), do: %{}

  defp prod_lines_of(ids) do
    Repo.all(from(l in OrderLine, where: l.order_id in ^ids, order_by: [asc: l.id]))
    |> Enum.map(
      &%{
        order_id: &1.order_id,
        product_id: &1.product_id || 0,
        quantity: &1.quantity || "",
        unit: &1.unit || "",
        amount: Xml.money_of(&1.amount)
      }
    )
    |> Enum.group_by(& &1.order_id)
  end

  defp idocs_of(company_id) do
    Repo.all(from(d in InternalDoc, where: d.company_id == ^company_id, order_by: [asc: d.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        number: &1.number || "",
        date: &1.doc_date || "",
        status: &1.status || ""
      }
    )
  end

  defp idoc_lines_of([]), do: %{}

  defp idoc_lines_of(ids) do
    Repo.all(
      from(l in InternalDocLine,
        where: l.doc_id in ^ids and l.line_kind == "product",
        order_by: [asc: l.id]
      )
    )
    |> Enum.map(
      &%{
        doc_id: &1.doc_id,
        product_id: &1.product_id || 0,
        quantity: &1.quantity || "",
        amount: Xml.money_of(&1.amount)
      }
    )
    |> Enum.group_by(& &1.doc_id)
  end
end

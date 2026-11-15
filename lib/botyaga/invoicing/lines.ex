defmodule Botyaga.Invoicing.Lines do
  @moduledoc "Редове на фактура, сборове и проверки на препратките към фирмата."

  import Ecto.Query

  alias Botyaga.{Catalog, Repo}
  alias Botyaga.Invoicing.{Invoice, InvoiceLine, Money}

  def prepare(company_id, head, self_id) do
    with :ok <- ensure_location(company_id, head.location_id),
         :ok <- ensure_original(company_id, head.original_invoice_id, self_id) do
      if head.counterpart_id <= 0 and head.document_type == "07" do
        {:ok, "Агенция Митници (Разчети с митници)"}
      else
        case Repo.get_by(Catalog.Counterpart, id: head.counterpart_id, company_id: company_id) do
          nil -> {:error, {422, "контрагентът не е намерен"}}
          counterpart -> {:ok, counterpart.name}
        end
      end
    end
  end

  def ensure_products(_company_id, nil), do: :ok

  def ensure_products(company_id, lines) do
    Enum.reduce_while(lines, :ok, fn line, _acc ->
      cond do
        line.product_id <= 0 ->
          {:cont, :ok}

        Repo.get_by(Catalog.Product, id: line.product_id, company_id: company_id) == nil ->
          {:halt, {:error, {422, "стоката не е намерена"}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp ensure_location(_company_id, location_id) when location_id <= 0, do: :ok

  defp ensure_location(company_id, location_id) do
    if Repo.get_by(Botyaga.Companies.Location, id: location_id, company_id: company_id) == nil do
      {:error, {422, "обектът не е намерен"}}
    else
      :ok
    end
  end

  defp ensure_original(_company_id, original_id, _self_id) when original_id <= 0, do: :ok

  defp ensure_original(_company_id, original_id, self_id) when original_id == self_id,
    do: {:error, {422, "известието не може да сочи към себе си"}}

  defp ensure_original(company_id, original_id, _self_id) do
    if Repo.get_by(Invoice, id: original_id, company_id: company_id) == nil do
      {:error, {422, "първоначалната фактура не е намерена"}}
    else
      :ok
    end
  end

  def totals(head, lines) do
    if head.document_type == "07" and String.trim(head.customs_statistical) != "" do
      s = Money.cents(head.customs_statistical) || 0
      d = Money.cents(head.customs_duty) || 0
      v = Money.cents(head.customs_vat) || 0
      {Money.money(s + d), Money.money(v), Money.money(s + d + v)}
    else
      {
        Money.sum_amounts(Enum.map(lines, & &1.net_amount)),
        Money.sum_amounts(Enum.map(lines, & &1.vat_amount)),
        Money.sum_amounts(Enum.map(lines, & &1.total_amount))
      }
    end
  end

  def insert_lines(invoice_id, company_id, lines) do
    Enum.each(lines, fn line -> insert_line(invoice_id, company_id, line) end)
  end

  defp insert_line(invoice_id, company_id, line) do
    code =
      if String.trim(line.code) == "" do
        product_code(line.product_id, company_id)
      else
        line.code
      end

    Repo.insert!(%InvoiceLine{
      invoice_id: invoice_id,
      code: String.trim(code),
      description: line.description,
      quantity: line.quantity,
      unit: String.trim(line.unit),
      unit_price: line.unit_price,
      vat_rate: String.trim(line.vat_rate),
      net_amount: line.net_amount,
      vat_amount: line.vat_amount,
      total_amount: line.total_amount,
      product_id: line.product_id
    })
  end

  def replace_lines(invoice_id, company_id, lines) do
    Repo.delete_all(from(l in InvoiceLine, where: l.invoice_id == ^invoice_id))
    insert_lines(invoice_id, company_id, lines)
  end

  defp product_code(product_id, _company_id) when product_id <= 0, do: ""

  defp product_code(product_id, company_id) do
    case Repo.get_by(Catalog.Product, id: product_id, company_id: company_id) do
      nil -> ""
      product -> product.code || ""
    end
  end
end

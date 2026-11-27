defmodule Botyaga.Printing.Protocol do
  @moduledoc """
  PDF протокол на производствен документ (поръчка, месечна карта, ръчен приход,
  комплектоване) — както CONTROLISY „Протоколът в PDF“.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Companies, Dec, Printing, Repo}
  alias Botyaga.Production.{Card, CardProduct, Order, OrderLine}
  alias Botyaga.Stock.{Kit, KitLine, ProductionReceipt, ProductionReceiptLine}

  def render(company_id, kind, id) do
    company = Repo.get(Companies.Company, company_id)
    cname = (company && company.name) || ""

    with {:ok, title, date, rows, total} <- load(company_id, kind, id) do
      blocks =
        [
          {:head, title},
          {:line, cname},
          {:line, "Дата: #{date}"},
          {:line, ""},
          {:table, [["Продукт", "Количество", "Ед. цена", "Стойност"] | rows]},
          {:totals, [["Общо", "", "", Dec.money(total)]]}
        ]

      case Printing.render(blocks, "pdf") do
        {:ok, bytes} ->
          {:ok, %{bytes: bytes, filename: "#{kind}-#{id}.pdf", mime: "application/pdf"}}

        error ->
          error
      end
    end
  end

  defp load(company_id, "production_order", id) do
    case Repo.get_by(Order, id: id, company_id: company_id) do
      nil ->
        {:error, {404, "няма поръчка"}}

      o ->
        lines = Repo.all(from(l in OrderLine, where: l.order_id == ^o.id, order_by: [asc: l.id]))
        rows = Enum.map(lines, fn l -> [name(l.product_id), l.quantity, "", ""] end)
        out = [name(o.output_product_id), o.quantity, "", o.material_cost]

        {:ok, "Протокол производство #{o.number}", o.order_date, rows ++ [out],
         Dec.or0(o.material_cost)}
    end
  end

  defp load(company_id, "production_card", id) do
    case Repo.get_by(Card, id: id, company_id: company_id) do
      nil ->
        {:error, {404, "няма карта"}}

      c ->
        rows =
          Repo.all(from(p in CardProduct, where: p.card_id == ^c.id, order_by: [asc: p.id]))
          |> Enum.map(fn p -> [name(p.product_id), p.quantity, "", p.cost] end)

        total = Enum.reduce(rows, 0, fn r, a -> a + Dec.or0(List.last(r)) end)
        {:ok, "Протокол месечно производство #{c.number}", c.month, rows, total}
    end
  end

  defp load(company_id, "production_receipt", id) do
    case Repo.get_by(ProductionReceipt, id: id, company_id: company_id) do
      nil ->
        {:error, {404, "няма приход"}}

      d ->
        rows =
          Repo.all(
            from(l in ProductionReceiptLine, where: l.doc_id == ^d.id, order_by: [asc: l.line_no])
          )
          |> Enum.map(fn l -> [name(l.product_id), l.quantity, l.unit_cost, l.amount] end)

        total = Enum.reduce(rows, 0, fn r, a -> a + Dec.or0(List.last(r)) end)
        {:ok, "Протокол ръчен приход #{d.number}", d.doc_date, rows, total}
    end
  end

  defp load(company_id, "kit", id) do
    case Repo.get_by(Kit, id: id, company_id: company_id) do
      nil ->
        {:error, {404, "няма комплектоване"}}

      k ->
        rows =
          Repo.all(from(l in KitLine, where: l.kit_id == ^k.id, order_by: [asc: l.id]))
          |> Enum.map(fn l -> [name(l.product_id), l.quantity, "", ""] end)

        out = [name(k.output_product_id), k.quantity, "", k.cost]
        {:ok, "Протокол комплектоване #{k.number}", k.doc_date, rows ++ [out], Dec.or0(k.cost)}
    end
  end

  defp load(_cid, _kind, _id), do: {:error, {400, "непознат вид документ"}}

  defp name(pid) do
    case Repo.get(Catalog.Product, pid) do
      nil -> ""
      p -> p.name
    end
  end
end

defmodule Botyaga.Stock.Replay.Load do
  @moduledoc "Зареждане на складовите движения от документите."

  import Ecto.Query

  alias Botyaga.{Catalog, Companies, Dec, Invoicing, Repo}
  alias Botyaga.Production.{Order, OrderLine}

  alias Botyaga.Stock.{
    InternalDoc,
    InternalDocLine,
    Kit,
    KitLine,
    MaterialIssue,
    MaterialIssueLine
  }

  alias Botyaga.Stock.Replay

  def load_products(company_id) do
    Repo.all(from(p in Catalog.Product, where: p.company_id == ^company_id))
    |> Map.new(fn p ->
      {p.id,
       %{
         name: p.name,
         is_inventory: p.is_inventory,
         inventory: p.inventory_account_id,
         revenue: p.revenue_account_id,
         expense: p.expense_account_id,
         auto_write_off: p.auto_write_off
       }}
    end)
  end

  def company_setup(company_id) do
    case Companies.get_company(company_id) do
      nil ->
        {1, "WAC"}

      company ->
        method =
          if company.inventory_valuation_method in ["FIFO", "LIFO"],
            do: company.inventory_valuation_method,
            else: "WAC"

        {company.fiscal_year_start_month, method}
    end
  end

  def product_name(products, id), do: (Map.get(products, id) || %{name: ""}).name

  defp push({items, dates}, date, rank, seq, mv) do
    if String.length(date) < 10 do
      {items, dates}
    else
      {items ++ [%{date: date, rank: rank, seq: seq, mv: mv}], dates ++ [date]}
    end
  end

  def load_opening({items, dates}, company_id, year, fy, products) do
    rows =
      Repo.all(
        from(o in Botyaga.Periods.OpeningBalance,
          where: o.company_id == ^company_id and o.fiscal_year == ^year and o.product_id > 0
        )
      )

    Enum.reduce(Enum.with_index(rows), {items, dates}, fn {r, i}, acc ->
      if keep?(products, r.product_id) do
        q = Dec.or0(r.quantity)

        if q > 0 and String.length(fy) >= 10 do
          value = Dec.or0(r.debit)
          push(acc, fy, 0, i, %{type: :open, product: r.product_id, qty: q, value: value})
        else
          acc
        end
      else
        acc
      end
    end)
  end

  def load_invoices({items, dates}, company_id, products) do
    rows =
      Repo.all(
        from(i in Invoicing.Invoice,
          join: l in Invoicing.InvoiceLine,
          on: l.invoice_id == i.id,
          where:
            i.company_id == ^company_id and i.status == "posted" and
              i.document_type in ["01", "11"],
          order_by: [asc: i.id, asc: l.id],
          select:
            {i.id, i.direction, i.issue_date, i.number, i.location_id, l.id, l.product_id,
             l.quantity, l.net_amount}
        )
      )

    Enum.reduce(Enum.with_index(rows), {items, dates}, fn {r, i}, acc ->
      {inv, dir, date, doc, loc, line, pid, quantity, net} = r

      if keep?(products, pid) do
        q = Dec.or0(quantity)

        if q > 0 do
          seq = inv * 1000 + i

          if dir == "in" do
            unit = Replay.unit_of(Dec.or0(net), q)

            push(acc, date, 1, seq, %{
              type: :in,
              product: pid,
              qty: q,
              unit: unit,
              loc: loc,
              inv: inv,
              line: line,
              doc: doc
            })
          else
            push(acc, date, 6, seq, %{
              type: :out,
              product: pid,
              qty: q,
              loc: loc,
              doc: doc,
              reason: "sale",
              sale: true,
              bucket: inv
            })
          end
        else
          acc
        end
      else
        acc
      end
    end)
  end

  def load_production({items, dates}, company_id, products) do
    orders =
      Repo.all(
        from(o in Order,
          where: o.company_id == ^company_id and o.status == "completed",
          order_by: [asc: o.id]
        )
      )

    Enum.reduce(orders, {items, dates}, fn order, acc ->
      lines =
        Repo.all(from(l in OrderLine, where: l.order_id == ^order.id, order_by: [asc: l.id]))

      acc =
        Enum.reduce(Enum.with_index(lines), acc, fn {line, i}, acc ->
          if keep?(products, line.product_id) do
            lq = Dec.or0(line.quantity)

            if lq > 0 do
              push(acc, order.order_date, 3, order.id * 1000 + i, %{
                type: :out,
                product: line.product_id,
                qty: lq,
                loc: order.location_id,
                doc: order.number,
                reason: "production",
                sale: false,
                bucket: order.id
              })
            else
              acc
            end
          else
            acc
          end
        end)

      if keep?(products, order.output_product_id) do
        q = Dec.or0(order.quantity)

        if q > 0 do
          push(acc, order.order_date, 4, order.id * 1000 + 999, %{
            type: :make,
            product: order.output_product_id,
            qty: q,
            loc: order.location_id,
            doc: order.number,
            order: order.id
          })
        else
          acc
        end
      else
        acc
      end
    end)
  end

  def load_kits({items, dates}, company_id, products) do
    kits =
      Repo.all(
        from(k in Kit,
          where: k.company_id == ^company_id and k.status == "completed",
          order_by: [asc: k.id]
        )
      )

    Enum.reduce(kits, {items, dates}, fn kit, acc ->
      lines = Repo.all(from(l in KitLine, where: l.kit_id == ^kit.id, order_by: [asc: l.id]))

      acc =
        Enum.reduce(Enum.with_index(lines), acc, fn {line, i}, acc ->
          if keep?(products, line.product_id) do
            lq = Dec.or0(line.quantity)

            if lq > 0 do
              push(acc, kit.doc_date, 3, kit.id * 1000 + i, %{
                type: :out,
                product: line.product_id,
                qty: lq,
                loc: kit.location_id,
                doc: kit.number,
                reason: "kit",
                sale: false,
                bucket: kit.id
              })
            else
              acc
            end
          else
            acc
          end
        end)

      if keep?(products, kit.output_product_id) do
        q = Dec.or0(kit.quantity)

        if q > 0 do
          push(acc, kit.doc_date, 4, kit.id * 1000 + 999, %{
            type: :make,
            product: kit.output_product_id,
            qty: q,
            loc: kit.location_id,
            doc: kit.number,
            order: kit.id
          })
        else
          acc
        end
      else
        acc
      end
    end)
  end

  def load_transfers({items, dates}, company_id, products) do
    docs =
      Repo.all(
        from(d in InternalDoc,
          where: d.company_id == ^company_id and d.status == "confirmed",
          order_by: [asc: d.id]
        )
      )

    Enum.reduce(docs, {items, dates}, fn doc, acc ->
      lines =
        Repo.all(from(l in InternalDocLine, where: l.doc_id == ^doc.id, order_by: [asc: l.id]))

      Enum.reduce(Enum.with_index(lines), acc, fn {line, i}, acc ->
        if line.line_kind == "product" and keep?(products, line.product_id) do
          q = Dec.or0(line.quantity)

          if q > 0 do
            push(acc, doc.doc_date, 2, doc.id * 1000 + i, %{
              type: :move,
              product: line.product_id,
              qty: q,
              from: doc.from_location_id,
              to: doc.to_location_id,
              doc: doc.number
            })
          else
            acc
          end
        else
          acc
        end
      end)
    end)
  end

  def load_issues({items, dates}, company_id, products) do
    docs =
      Repo.all(
        from(d in MaterialIssue,
          where: d.company_id == ^company_id and d.status == "confirmed",
          order_by: [asc: d.id]
        )
      )

    Enum.reduce(docs, {items, dates}, fn doc, acc ->
      lines =
        Repo.all(
          from(l in MaterialIssueLine,
            where: l.doc_id == ^doc.id,
            order_by: [asc: l.line_no, asc: l.id]
          )
        )

      Enum.reduce(Enum.with_index(lines), acc, fn {line, i}, acc ->
        if keep?(products, line.product_id) do
          q = Dec.or0(line.quantity)

          if q > 0 do
            push(acc, doc.doc_date, 5, doc.id * 1000 + i, %{
              type: :out,
              product: line.product_id,
              qty: q,
              loc: doc.location_id,
              doc: doc.number,
              reason: "material",
              sale: false,
              bucket: doc.id
            })
          else
            acc
          end
        else
          acc
        end
      end)
    end)
  end

  def horizon_of(until, dates) do
    far = String.trim(until) == "" or String.starts_with?(until, "9999")

    if not far do
      String.trim(until)
    else
      today = Date.utc_today() |> Date.to_iso8601()
      Enum.reduce(dates, today, fn d, h -> if d > h, do: d, else: h end)
    end
  end

  def fy_start(date, start_month) do
    y = date |> String.slice(0, 4) |> to_int(2026)
    m = date |> String.slice(5, 2) |> to_int(1)
    sm = if start_month in 1..12, do: start_month, else: 1
    year = if m >= sm, do: y, else: y - 1
    {year, "#{year}-#{pad2(sm)}-01"}
  end

  ## Прилагане на движенията

  defp to_int(value, default) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp keep?(products, id) do
    case Map.get(products, id) do
      %{is_inventory: 1, auto_write_off: 0} -> true
      _ -> false
    end
  end
end

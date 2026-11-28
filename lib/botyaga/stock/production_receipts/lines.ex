defmodule Botyaga.Stock.ProductionReceipts.Lines do
  @moduledoc """
  Таб 1 "Произведено" и редове на документа: продаденото по КТ 701 за месеца,
  изграждане и преизчисляване на редовете на ръчния приход на продукция.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Params, Repo}
  alias Botyaga.Invoicing.{Invoice, InvoiceLine}

  alias Botyaga.Stock.{ProductionReceiptLine, Rules}
  alias Botyaga.Stock.ProductionReceipts.{Alloc, Internal}

  ## Таб 1 — продадено по КТ 701 за месеца

  def sold_by_product(company_id, month, products) do
    rows =
      Repo.all(
        from(i in Invoice,
          join: l in InvoiceLine,
          on: l.invoice_id == i.id,
          where:
            i.company_id == ^company_id and i.status == "posted" and i.direction == "out" and
              i.document_type in ["01", "11"] and l.product_id > 0 and
              like(i.issue_date, ^"#{month}%"),
          select: {l.product_id, l.quantity, l.net_amount}
        )
      )

    Enum.reduce(rows, %{}, fn {pid, q, net}, acc ->
      if Map.has_key?(products, pid) do
        p = Map.fetch!(products, pid)

        if p.inventory_account_id > 0 and p.revenue_account_id > 0 do
          cur = Map.get(acc, pid, %{qty: 0, revenue: 0})
          Map.put(acc, pid, %{qty: cur.qty + Dec.or0(q), revenue: cur.revenue + Dec.or0(net)})
        else
          acc
        end
      else
        acc
      end
    end)
  end

  ## Редове на документа

  def products_map(company_id) do
    Repo.all(from(p in Catalog.Product, where: p.company_id == ^company_id))
    |> Map.new(&{&1.id, &1})
  end

  # Стойността на произведеното идва от натрупаното в 611 за месеца:
  # единична цена = 611 / общо произведено; по ред = произведено × единична.
  def build_lines(company_id, month, params) do
    products = products_map(company_id)
    sold = sold_by_product(company_id, month, products)

    arr =
      case Map.get(params, "lines") do
        list when is_list(list) -> list
        _ -> []
      end

    ending =
      Enum.reduce(arr, %{}, fn l, acc ->
        pid = Params.integer(l, "product_id") || 0

        case Internal.qty_of(Map.get(l, "ending_quantity")) do
          {:ok, q} ->
            Map.put(
              acc,
              pid,
              {q, Internal.pick(l, "coefficient", "1"), Internal.pick(l, "manual_amount", "")}
            )

          _ ->
            acc
        end
      end)

    ids =
      (Map.keys(sold) ++ Map.keys(ending))
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(products, &1))
      |> Enum.sort()

    rows =
      Enum.reduce(ids, [], fn pid, acc ->
        p = Map.fetch!(products, pid)
        s = Map.get(sold, pid, %{qty: 0, revenue: 0})
        {end_qty, coef, manual} = Map.get(ending, pid, {0, "1", ""})
        acc ++ [{p, s.qty, end_qty, coef, manual}]
      end)

    case Enum.reduce_while(rows, {:ok, []}, fn {p, sold_qty, end_qty, coef, manual}, {:ok, acc} ->
           case product_ok(company_id, p) do
             :ok ->
               {:cont,
                {:ok,
                 acc ++
                   [
                     %{
                       id: p.id,
                       product: p,
                       sold_quantity: sold_qty,
                       ending_quantity: end_qty,
                       quantity: sold_qty + end_qty,
                       coefficient: coef,
                       manual_amount: manual
                     }
                   ]}}

             {:error, _} = err ->
               {:halt, err}
           end
         end) do
      {:ok, []} ->
        {:error, {422, "няма артикули за месеца — проверете продажбите по КТ 701"}}

      {:ok, prepared} ->
        expense_total = expense_total(company_id, month, params)
        available = expense_total - wip_end(params, expense_total)
        amounts = line_amounts(prepared, available)

        {:ok,
         Enum.zip(prepared, amounts)
         |> Enum.map(fn {r, amount} ->
           p = r.product
           unit = if r.quantity > 0, do: Dec.div(amount, r.quantity) || 0, else: 0

           %{
             product_id: p.id,
             sold_quantity: r.sold_quantity,
             sold_amount: Dec.mul(r.sold_quantity, unit),
             ending_quantity: r.ending_quantity,
             quantity: r.quantity,
             unit_cost: unit,
             amount: amount,
             coefficient: r.coefficient,
             manual_amount: r.manual_amount,
             inventory_account_id: p.inventory_account_id,
             revenue_account_id: p.revenue_account_id,
             expense_account_id: expense_account(company_id, p)
           }
         end)}

      {:error, _} = err ->
        err
    end
  end

  # При потвърждаване стойностите се преизчисляват от текущия оборот на 611.
  def recompute_lines(company_id, month, lines, doc) do
    expense_total = expense_total(company_id, month, %{})
    wip = %{"wip_end_mode" => doc.wip_end_mode, "wip_end_value" => doc.wip_end_value}
    available = expense_total - wip_end(wip, expense_total)

    rows =
      Enum.map(lines, fn l ->
        %{
          id: l.product_id,
          quantity: Dec.or0(l.sold_quantity) + Dec.or0(l.ending_quantity),
          coefficient: l.coefficient,
          manual_amount: l.manual_amount
        }
      end)

    amounts = line_amounts(rows, available)

    Enum.zip(lines, amounts)
    |> Enum.map(fn {l, amount} ->
      sold = Dec.or0(l.sold_quantity)
      end_qty = Dec.or0(l.ending_quantity)
      qty = sold + end_qty
      unit = if qty > 0, do: Dec.div(amount, qty) || 0, else: 0

      %{
        product_id: l.product_id,
        sold_quantity: sold,
        sold_amount: Dec.mul(sold, unit),
        ending_quantity: end_qty,
        quantity: qty,
        unit_cost: unit,
        amount: amount,
        coefficient: l.coefficient,
        manual_amount: l.manual_amount,
        inventory_account_id: l.inventory_account_id,
        revenue_account_id: l.revenue_account_id,
        expense_account_id: l.expense_account_id
      }
    end)
  end

  # Незавършено производство: част от 611, която остава за следващия месец.
  def wip_end(src, available) do
    case Internal.pick(src, "wip_end_mode", "amount") do
      "percent" ->
        Dec.div(
          Dec.mul(available, Dec.or0(Internal.pick(src, "wip_end_value", "0"))),
          100 * Dec.scale()
        ) ||
          0

      _ ->
        Dec.or0(Internal.pick(src, "wip_end_value", "0"))
    end
  end

  # Разпределение: ръчна сума има предност; останалото по количество×коефициент.
  def line_amounts(rows, available) do
    manual_sum =
      Enum.reduce(rows, 0, fn r, a ->
        a + if(r.manual_amount != "", do: Dec.or0(r.manual_amount), else: 0)
      end)

    rest = available - manual_sum
    auto = Enum.filter(rows, &(&1.manual_amount == ""))
    weight = fn r -> Dec.mul(r.quantity, Dec.or0(r.coefficient)) end
    tw = Enum.reduce(auto, 0, &(&2 + weight.(&1)))

    auto_map =
      if tw > 0 do
        list = Enum.map(auto, fn r -> {r.id, Dec.div(Dec.mul(rest, weight.(r)), tw) || 0} end)
        sum = Enum.reduce(list, 0, &(&2 + elem(&1, 1)))
        diff = rest - sum

        list =
          case list do
            [] ->
              []

            l ->
              {lid, lv} = List.last(l)
              List.replace_at(l, length(l) - 1, {lid, lv + diff})
          end

        Map.new(list)
      else
        Map.new(auto, &{&1.id, 0})
      end

    Enum.map(rows, fn r ->
      if r.manual_amount != "", do: Dec.or0(r.manual_amount), else: Map.get(auto_map, r.id, 0)
    end)
  end

  # Натрупаната стойност в 611 за месеца (нетен дебитен оборот по префикс 611).
  def expense_total(company_id, month, params) do
    prefix = Internal.prefix(params, "expense_prefix", "611")

    Alloc.net_turnover(company_id, month, prefix, "")
    |> Enum.reduce(0, fn a, s -> s + a.amount end)
  end

  def product_ok(company_id, p) do
    cond do
      p.inventory_account_id <= 0 ->
        {:error, {422, "артикулът #{p.name} няма сметка за наличност (303)"}}

      p.revenue_account_id <= 0 ->
        {:error, {422, "артикулът #{p.name} няма приходна сметка (701)"}}

      expense_account(company_id, p) <= 0 ->
        {:error, {422, "артикулът #{p.name} няма разходна сметка (611)"}}

      true ->
        :ok
    end
  end

  # 611: от артикула, иначе clearing сметката от правилото за продукция
  def expense_account(company_id, p) do
    if p.expense_account_id > 0 do
      p.expense_account_id
    else
      case Rules.pair(
             Rules.load(company_id),
             "production",
             p.inventory_account_id,
             p.revenue_account_id
           ) do
        %{clearing_account_id: c} when c > 0 -> c
        _ -> 0
      end
    end
  end

  def insert_lines(doc_id, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, no} ->
      Repo.insert!(%ProductionReceiptLine{
        doc_id: doc_id,
        line_no: no,
        product_id: line.product_id,
        sold_quantity: Dec.qty(line.sold_quantity),
        sold_amount: Dec.money(line.sold_amount),
        ending_quantity: Dec.qty(line.ending_quantity),
        quantity: Dec.qty(line.quantity),
        unit_cost: Dec.text(line.unit_cost, 6),
        amount: Dec.money(line.amount),
        allocated_amount: "0.00",
        writeoff_amount: "0.00",
        inventory_account_id: line.inventory_account_id,
        revenue_account_id: line.revenue_account_id,
        expense_account_id: line.expense_account_id,
        coefficient: line.coefficient,
        manual_amount: line.manual_amount
      })
    end)
  end
end

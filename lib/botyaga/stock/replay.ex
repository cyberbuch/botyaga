defmodule Botyaga.Stock.Replay do
  @moduledoc """
  Наличността се сглобява от документите по дата, не по реда на запис.
  WAC (среднопретеглена), FIFO и LIFO по партиди. Зареждането е в `Replay.Load`.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Repo}
  alias Botyaga.Stock.Lot
  alias Botyaga.Stock.Replay.Load

  def rebuild(company_id, until), do: run(company_id, until, true)
  def explain(company_id, until), do: run(company_id, until, false)

  defp run(company_id, until, write) do
    products = Load.load_products(company_id)
    {start_month, method} = Load.company_setup(company_id)

    {items, dates} =
      {[], []}
      |> Load.load_invoices(company_id, products)
      |> Load.load_production(company_id, products)
      |> Load.load_kits(company_id, products)
      |> Load.load_transfers(company_id, products)
      |> Load.load_issues(company_id, products)

    horizon = Load.horizon_of(until, dates)
    {year, fy} = Load.fy_start(horizon, start_month)
    {items, _dates} = Load.load_opening({items, dates}, company_id, year, fy, products)

    items =
      items
      |> Enum.filter(&(&1.date >= fy and &1.date <= horizon))
      |> Enum.sort_by(&{&1.date, &1.rank, &1.seq})

    {warnings, sales, flows, states, books} = apply_moves(items, products, method)
    balances = balances_of(states, products)

    if write do
      persist(products, states)
      Botyaga.Stock.Journal.strip_legacy(company_id)
      warnings = Botyaga.Stock.Journal.rewrite(company_id, products, books, warnings)
      {:ok, %{warnings: warnings, sales: sales, flows: flows, balances: balances}}
    else
      {:ok, %{warnings: warnings, sales: sales, flows: flows, balances: balances}}
    end
  end

  defp apply_moves(items, products, method) do
    {states, warnings, sales, flows, made, spent, _order_cost} =
      Enum.reduce(items, {%{}, [], [], [], [], [], %{}}, fn it,
                                                            {states, warnings, sales, flows, made,
                                                             spent, order_cost} ->
        pid = it.mv.product
        st = Map.get(states, pid, %{qty: 0, val: 0, lots: []})
        name = Load.product_name(products, pid)

        case it.mv.type do
          :open ->
            st = %{st | qty: st.qty + it.mv.qty, val: st.val + it.mv.value}

            st = %{
              st
              | lots:
                  st.lots ++
                    [
                      %{
                        loc: 0,
                        rem: it.mv.qty,
                        unit: unit_of(it.mv.value, it.mv.qty),
                        date: it.date,
                        inv: 0,
                        line: 0
                      }
                    ]
            }

            flows =
              flows ++
                [
                  flow(
                    products,
                    it.date,
                    "начало",
                    "in",
                    "opening",
                    pid,
                    0,
                    it.mv.qty,
                    it.mv.value
                  )
                ]

            {Map.put(states, pid, st), warnings, sales, flows, made, spent, order_cost}

          :in ->
            value = Dec.mul(it.mv.qty, it.mv.unit)
            st = receive(st, it.mv.qty, it.mv.unit, it.mv.loc, it.date, it.mv.inv, it.mv.line)

            flows =
              flows ++
                [
                  flow(
                    products,
                    it.date,
                    it.mv.doc,
                    "in",
                    "purchase",
                    pid,
                    it.mv.loc,
                    it.mv.qty,
                    value
                  )
                ]

            {Map.put(states, pid, st), warnings, sales, flows, made, spent, order_cost}

          :out ->
            {st, cost, miss} = issue(st, it.mv.qty, it.mv.loc, method)

            warnings =
              if miss > 0, do: warnings ++ ["#{name}: липсват #{Dec.qty(miss)}"], else: warnings

            covered = max(it.mv.qty - miss, 0)

            flows =
              flows ++
                [
                  flow(
                    products,
                    it.date,
                    it.mv.doc,
                    "out",
                    it.mv.reason,
                    pid,
                    it.mv.loc,
                    covered,
                    cost
                  )
                ]

            {made, spent, order_cost} =
              case it.mv.reason do
                "production" ->
                  {made ++ [%{doc: it.mv.bucket, product: pid, qty: covered, cost: cost}], spent,
                   Map.update(order_cost, it.mv.bucket, cost, &(&1 + cost))}

                "kit" ->
                  {made ++ [%{doc: it.mv.bucket, product: pid, qty: covered, cost: cost}], spent,
                   Map.update(order_cost, it.mv.bucket, cost, &(&1 + cost))}

                "material" ->
                  {made, spent ++ [%{doc: it.mv.bucket, product: pid, qty: covered, cost: cost}],
                   order_cost}

                _ ->
                  {made, spent, order_cost}
              end

            sales =
              if it.mv.sale do
                meta = Map.get(products, pid)

                sales ++
                  [
                    %{
                      product_id: pid,
                      product_name: name,
                      date: it.date,
                      cost: cost,
                      inventory_account_id: (meta && meta.inventory) || 0,
                      revenue_account_id: (meta && meta.revenue) || 0,
                      expense_account_id: (meta && meta.expense) || 0
                    }
                  ]
              else
                sales
              end

            {Map.put(states, pid, st), warnings, sales, flows, made, spent, order_cost}

          :move ->
            {st, moved, value, miss} = transfer(st, it.mv.qty, it.mv.from, it.mv.to, it.date)

            warnings =
              if miss > 0,
                do: warnings ++ ["#{name}: липсват #{Dec.qty(miss)} за трансфер"],
                else: warnings

            flows =
              flows ++
                [
                  flow(
                    products,
                    it.date,
                    it.mv.doc,
                    "out",
                    "transfer",
                    pid,
                    it.mv.from,
                    moved,
                    value
                  ),
                  flow(
                    products,
                    it.date,
                    it.mv.doc,
                    "in",
                    "transfer",
                    pid,
                    it.mv.to,
                    moved,
                    value
                  )
                ]

            {Map.put(states, pid, st), warnings, sales, flows, made, spent, order_cost}

          :make ->
            total = Map.get(order_cost, it.mv.order, 0)
            unit = if it.mv.qty > 0, do: Dec.div(total, it.mv.qty) || 0, else: 0
            st = receive(st, it.mv.qty, unit, it.mv.loc, it.date, 0, 0)

            flows =
              flows ++
                [
                  flow(
                    products,
                    it.date,
                    it.mv.doc,
                    "in",
                    "production",
                    pid,
                    it.mv.loc,
                    it.mv.qty,
                    total
                  )
                ]

            {Map.put(states, pid, st), warnings, sales, flows, made, spent, order_cost}
        end
      end)

    flows = Enum.filter(flows, fn f -> Dec.or0(f.quantity) > 0 or Dec.or0(f.value) > 0 end)
    books = books_with(items, made, spent)
    {warnings, sales, flows, states, books}
  end

  defp books_with(items, made, spent) do
    {prods, uses, _seen_p, _seen_u} =
      Enum.reduce(items, {[], [], MapSet.new(), MapSet.new()}, fn it,
                                                                  {prods, uses, seen_p, seen_u} ->
        case it.mv do
          %{type: :make, order: order} ->
            if MapSet.member?(seen_p, order) do
              {prods, uses, seen_p, seen_u}
            else
              {prods ++
                 [%{id: order, number: it.mv.doc, output_id: it.mv.product, date: it.date}], uses,
               MapSet.put(seen_p, order), seen_u}
            end

          %{type: :out, reason: "material", bucket: bucket} ->
            if MapSet.member?(seen_u, bucket) do
              {prods, uses, seen_p, seen_u}
            else
              {prods, uses ++ [%{id: bucket, number: it.mv.doc, date: it.date}], seen_p,
               MapSet.put(seen_u, bucket)}
            end

          _ ->
            {prods, uses, seen_p, seen_u}
        end
      end)

    %{prods: prods, uses: uses, made: made, spent: spent}
  end

  defp receive(st, q, _unit, _loc, _date, _inv, _line) when q <= 0, do: st

  defp receive(st, q, unit, loc, date, inv, line) do
    add = Dec.mul(q, unit)

    %{
      st
      | qty: st.qty + q,
        val: st.val + add,
        lots: st.lots ++ [%{loc: loc, rem: q, unit: unit, date: date, inv: inv, line: line}]
    }
  end

  defp issue(st, q, _loc, _method) when q <= 0, do: {st, 0, 0}

  defp issue(st, q, loc, method) do
    if method in ["FIFO", "LIFO"] do
      issue_lots(st, q, loc, method == "LIFO")
    else
      covered = min(q, max(st.qty, 0))
      miss = q - covered

      if covered <= 0 do
        {st, 0, miss}
      else
        unit = if st.qty > 0, do: Dec.div(st.val, st.qty) || 0, else: 0
        cost = Dec.mul(covered, unit)

        {st, cost} =
          if st.qty - covered <= 0 do
            {%{st | qty: 0, val: 0}, st.val}
          else
            {%{st | qty: st.qty - covered, val: st.val - cost}, cost}
          end

        st = consume(st, loc, covered)
        {st, cost, miss}
      end
    end
  end

  defp issue_lots(st, q, loc, lifo) do
    idx =
      st.lots
      |> Enum.with_index()
      |> Enum.filter(fn {l, _i} -> l.loc == loc and l.rem > 0 end)
      |> Enum.map(fn {_l, i} -> i end)

    idx = if lifo, do: Enum.reverse(idx), else: idx

    {lots, need, cost} =
      Enum.reduce(idx, {st.lots, q, 0}, fn i, {lots, need, cost} ->
        if need <= 0 do
          {lots, need, cost}
        else
          lot = Enum.at(lots, i)
          take = min(lot.rem, need)
          cost = cost + Dec.mul(take, lot.unit)
          {List.replace_at(lots, i, %{lot | rem: lot.rem - take}), need - take, cost}
        end
      end)

    st = %{st | lots: lots}
    covered = q - need

    if covered > 0 do
      if st.qty - covered <= 0 do
        {%{st | qty: 0, val: 0}, st.val, need}
      else
        {%{st | qty: st.qty - covered, val: st.val - cost}, cost, need}
      end
    else
      {st, cost, need}
    end
  end

  defp consume(st, loc, need) do
    {lots, _need} =
      Enum.reduce(0..1, {st.lots, need}, fn pass, {lots, need} ->
        Enum.reduce(Enum.with_index(lots), {lots, need}, fn {lot, i}, {lots, need} ->
          here = if pass == 0, do: lot.loc == loc, else: lot.loc != loc

          if need <= 0 or not here or lot.rem <= 0 do
            {lots, need}
          else
            take = min(lot.rem, need)
            {List.replace_at(lots, i, %{lot | rem: lot.rem - take}), need - take}
          end
        end)
      end)

    %{st | lots: lots}
  end

  defp transfer(st, q, from, to, date) do
    {lots, need, value, born} =
      Enum.reduce(st.lots, {st.lots, q, 0, []}, fn lot, {lots, need, value, born} ->
        if need <= 0 or lot.loc != from or lot.rem <= 0 do
          {lots, need, value, born}
        else
          take = min(lot.rem, need)
          value = value + Dec.mul(take, lot.unit)
          idx = Enum.find_index(lots, &(&1 == lot))
          lots = List.replace_at(lots, idx, %{lot | rem: lot.rem - take})

          born =
            born ++
              [%{loc: to, rem: take, unit: lot.unit, date: date, inv: lot.inv, line: lot.line}]

          {lots, need - take, value, born}
        end
      end)

    {%{st | lots: lots ++ born}, q - need, value, need}
  end

  def unit_of(value, q), do: if(q > 0, do: Dec.div(value, q) || 0, else: 0)

  defp flow(products, date, doc, kind, reason, product, loc, q, value) do
    %{
      date: date,
      doc: doc,
      kind: kind,
      reason: reason,
      product_id: product,
      product_name: Load.product_name(products, product),
      location_id: loc,
      quantity: Dec.qty(q),
      value: Dec.money(value)
    }
  end

  defp balances_of(states, products) do
    states
    |> Enum.reject(fn {_pid, st} -> st.qty <= 0 and Enum.all?(st.lots, &(&1.rem <= 0)) end)
    |> Enum.flat_map(fn {pid, st} ->
      by =
        st.lots
        |> Enum.filter(&(&1.rem > 0))
        |> Enum.reduce(%{}, fn lot, acc -> Map.update(acc, lot.loc, lot.rem, &(&1 + lot.rem)) end)

      by = if by == %{} and st.qty > 0, do: %{0 => st.qty}, else: by
      sum = by |> Map.values() |> Enum.sum()
      total = map_size(by)

      {rows, _left, _n} =
        Enum.reduce(by, {[], st.val, 0}, fn {loc, q}, {rows, left, n} ->
          n = n + 1

          val =
            cond do
              n == total ->
                left

              sum > 0 ->
                v = Dec.div(Dec.mul(st.val, q), sum) || 0
                v

              true ->
                0
            end

          left = if n == total or sum <= 0, do: left, else: left - val

          {rows ++
             [
               %{
                 product_id: pid,
                 product_name: Load.product_name(products, pid),
                 location_id: loc,
                 quantity: Dec.qty(q),
                 value: Dec.money(val)
               }
             ], left, n}
        end)

      rows
    end)
    |> Enum.sort_by(&{&1.product_name, &1.location_id})
  end

  ## Запис

  defp persist(products, states) do
    Enum.each(products, fn {id, meta} ->
      if meta.is_inventory == 1 do
        Repo.delete_all(from(l in Lot, where: l.product_id == ^id))
        st = Map.get(states, id)
        {q, val} = if st, do: {st.qty, st.val}, else: {0, 0}
        cost = if q > 0, do: Dec.text(Dec.div(val, q) || 0, 6), else: "0.000000"

        Repo.update_all(from(p in Catalog.Product, where: p.id == ^id),
          set: [stock_quantity: Dec.qty(q), stock_value: Dec.money(val), cost_price: cost]
        )

        if st do
          Enum.each(st.lots, fn lot ->
            if lot.rem > 0 do
              Repo.insert!(%Lot{
                product_id: id,
                invoice_id: lot.inv,
                invoice_line_id: lot.line,
                received_date: lot.date,
                quantity: Dec.qty(lot.rem),
                quantity_remaining: Dec.qty(lot.rem),
                unit_cost: Dec.text(lot.unit, 6),
                location_id: lot.loc
              })
            end
          end)
        end
      end
    end)
  end

  ## Зареждане на движения
end

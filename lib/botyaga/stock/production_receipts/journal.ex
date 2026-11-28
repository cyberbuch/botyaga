defmodule Botyaga.Stock.ProductionReceipts.Journal do
  @moduledoc """
  Таб 3 "Записи": journal запис при потвърждаване на ръчния приход —
  ДТ 303 КТ 611 (приход на продукция), ДТ 303 КТ 612 (разпределение)
  и ДТ 701 КТ 303 за продаденото.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Repo}
  alias Botyaga.Catalog.Account

  alias Botyaga.Stock.{ProductionReceiptAllocation, ProductionReceiptLine}
  alias Botyaga.Stock.ProductionReceipts.Alloc

  ## Таб 3 — journal запис при потвърждаване

  def sides(company_id, lines, allocs, _indirect_total) do
    with {:ok, accounts} <- accounts_by_id(company_id, lines, allocs) do
      receipt =
        Enum.flat_map(lines, fn l ->
          amt = l.amount

          if amt > 0 do
            [
              %{
                account: Map.fetch!(accounts, l.inventory_account_id),
                direction: "debit",
                amount: Dec.money(amt)
              },
              %{
                account: Map.fetch!(accounts, l.expense_account_id),
                direction: "credit",
                amount: Dec.money(amt)
              }
            ]
          else
            []
          end
        end)

      dist =
        Enum.flat_map(allocs, fn a ->
          amt = a.amount

          if amt > 0 do
            line = Enum.find(lines, &(&1.product_id == a.product_id))

            [
              %{
                account: Map.fetch!(accounts, line.inventory_account_id),
                direction: "debit",
                amount: Dec.money(amt)
              },
              %{
                account: Map.fetch!(accounts, a.account_id),
                direction: "credit",
                amount: Dec.money(amt)
              }
            ]
          else
            []
          end
        end)

      alloc_by_product =
        Enum.reduce(allocs, %{}, fn a, acc ->
          Map.update(acc, a.product_id, a.amount, &(&1 + a.amount))
        end)

      writeoff =
        Enum.flat_map(lines, fn l ->
          q = l.quantity
          sold = l.sold_quantity
          full = l.amount + Map.get(alloc_by_product, l.product_id, 0)
          w = if q > 0 and sold > 0, do: Dec.mul(sold, Dec.div(full, q) || 0) || 0, else: 0
          w = Alloc.round_to_money(w)

          if w > 0 do
            [
              %{
                account: Map.fetch!(accounts, l.revenue_account_id),
                direction: "debit",
                amount: Dec.money(w)
              },
              %{
                account: Map.fetch!(accounts, l.inventory_account_id),
                direction: "credit",
                amount: Dec.money(w)
              }
            ]
          else
            []
          end
        end)

      sides = (receipt ++ dist ++ writeoff) |> Enum.filter(&(&1.amount != "0.00"))

      total =
        sides
        |> Enum.filter(&(&1.direction == "debit"))
        |> Enum.reduce(0, &(&2 + Dec.or0(&1.amount)))
        |> Dec.money()

      {:ok, sides, %{total: total}}
    end
  end

  def accounts_by_id(company_id, lines, allocs) do
    ids =
      (Enum.flat_map(
         lines,
         &[&1.inventory_account_id, &1.revenue_account_id, &1.expense_account_id]
       ) ++
         Enum.map(allocs, & &1.account_id))
      |> Enum.uniq()
      |> Enum.filter(&(&1 > 0))

    found =
      Repo.all(from(a in Account, where: a.company_id == ^company_id and a.id in ^ids))
      |> Map.new(&{&1.id, &1})

    missing = Enum.find(ids, &(Map.get(found, &1) == nil))

    if missing do
      {:error, {422, "липсва сметка с id #{missing}"}}
    else
      {:ok, found}
    end
  end

  def persist_lines(doc_id, lines, allocs) do
    alloc_by_product =
      Enum.reduce(allocs, %{}, fn a, acc ->
        Map.update(acc, a.product_id, a.amount, &(&1 + a.amount))
      end)

    Enum.each(lines, fn l ->
      q = l.quantity
      sold = l.sold_quantity
      full = l.amount + Map.get(alloc_by_product, l.product_id, 0)

      w =
        if q > 0 and sold > 0,
          do: Alloc.round_to_money(Dec.mul(sold, Dec.div(full, q) || 0) || 0),
          else: 0

      alloc = Map.get(alloc_by_product, l.product_id, 0)

      Repo.update_all(
        from(x in ProductionReceiptLine,
          where: x.doc_id == ^doc_id and x.product_id == ^l.product_id
        ),
        set: [
          sold_quantity: Dec.qty(l.sold_quantity),
          sold_amount: Dec.money(l.sold_amount),
          ending_quantity: Dec.qty(l.ending_quantity),
          quantity: Dec.qty(l.quantity),
          unit_cost: Dec.text(l.unit_cost, 6),
          amount: Dec.money(l.amount),
          allocated_amount: Dec.money(alloc),
          writeoff_amount: Dec.money(w),
          coefficient: l.coefficient,
          manual_amount: l.manual_amount
        ]
      )
    end)
  end

  # Без натрупана стойност в 611 и без непреки разходи няма какво да се запише.
  def values_present(lines) do
    if Enum.any?(lines, &(&1.amount > 0)) do
      :ok
    else
      {:error, {422, "няма натрупана стойност в 611 за месеца — записът на разходи липсва"}}
    end
  end

  def insert_allocations(doc_id, allocs) do
    allocs
    |> Enum.with_index(1)
    |> Enum.each(fn {a, no} ->
      Repo.insert!(%ProductionReceiptAllocation{
        doc_id: doc_id,
        line_no: no,
        product_id: a.product_id,
        account_id: a.account_id,
        base_amount: Dec.money(a.base_amount),
        amount: Dec.money(a.amount)
      })
    end)
  end
end

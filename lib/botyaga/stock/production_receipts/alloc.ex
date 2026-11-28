defmodule Botyaga.Stock.ProductionReceipts.Alloc do
  @moduledoc """
  Таб 2 "Разпределение 612": натрупаните непреки разходи по 612 (без 61201)
  се разпределят пропорционално на произведената стойност по ред.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Repo}
  alias Botyaga.Catalog.Account
  alias Botyaga.Journal.Entry

  alias Botyaga.Stock.ProductionReceipts.Internal

  ## Таб 2 — разпределение на натрупаните непреки разходи по 612

  # Числов (скалиран) списък за разпределение; в preview се форматира.
  def indirect_accounts(company_id, month, params) do
    prefix = Internal.prefix(params, "indirect_prefix", "612")
    exclude = Internal.prefix(params, "indirect_exclude", "61201")
    net_turnover(company_id, month, prefix, exclude) |> Enum.filter(&(&1.amount > 0))
  end

  def indirect_json(company_id, month, params) do
    indirect_accounts(company_id, month, params)
    |> Enum.map(fn a ->
      %{account_id: a.account_id, number: a.number, name: a.name, amount: Dec.money(a.amount)}
    end)
  end

  # Нетен оборот (дебит - кредит) по сметки с префикс за месеца, само положителен.
  def turnover(company_id, month, prefix, exclude) do
    net_turnover(company_id, month, prefix, exclude)
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.map(fn a ->
      %{account_id: a.account_id, number: a.number, name: a.name, amount: Dec.money(a.amount)}
    end)
    |> Enum.sort_by(& &1.number)
  end

  def net_turnover(company_id, month, prefix, exclude) do
    rows =
      Repo.all(
        from(e in Entry,
          join: l in Botyaga.Journal.Line,
          on: l.entry_id == e.id,
          join: a in Account,
          on: a.id == l.account_id,
          where:
            e.company_id == ^company_id and like(e.entry_date, ^"#{month}%") and
              like(a.number, ^"#{prefix}%"),
          select: {a.id, a.number, a.name, l.direction, l.amount}
        )
      )

    rows
    |> Enum.reject(fn {_id, num, _name, _dir, _amt} ->
      exclude != "" and String.starts_with?(num, exclude)
    end)
    |> Enum.reduce(%{}, fn {id, num, name, dir, amt}, acc ->
      v = if dir == "debit", do: Dec.or0(amt), else: -Dec.or0(amt)
      cur = Map.get(acc, id, %{account_id: id, number: num, name: name, amount: 0})
      Map.put(acc, id, %{cur | amount: cur.amount + v})
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.number)
  end

  # Разпределение пропорционално на произведената стойност (amount) по ред.
  def allocations(company_id, month, lines, params) do
    indirect = indirect_accounts(company_id, month, params)
    total_base = lines |> Enum.reduce(0, fn l, s -> s + l.amount end)

    {allocs, indirect_total} =
      Enum.reduce(indirect, {[], 0}, fn acc, {rows_acc, tot} ->
        amt = acc.amount
        per_line = split_share(amt, total_base, lines)

        rows =
          per_line
          |> Enum.map(fn {line, share} ->
            %{
              product_id: line.product_id,
              account_id: acc.account_id,
              base_amount: line.amount,
              amount: share
            }
          end)
          |> Enum.filter(&(&1.amount != 0))

        {rows_acc ++ rows, tot + amt}
      end)

    {:ok, allocs, indirect_total}
  end

  # Пропорционално разпределение с закръгляне до стотинки; последният ред поема остатъка.
  def split_share(total, base, lines) do
    with_base = Enum.filter(lines, &(&1.amount > 0))

    if base <= 0 or with_base == [] do
      Enum.map(lines, &{&1, 0})
    else
      rounded =
        Enum.reduce(with_base, [], fn line, acc ->
          raw = Dec.mul(total, Dec.div(line.amount, base) || 0) || 0
          acc ++ [{line, round_to_money(raw)}]
        end)

      sum = Enum.reduce(rounded, 0, fn {_l, r}, s -> s + r end)
      diff = round_to_money(total) - sum

      rounded =
        if diff != 0 and rounded != [] do
          {last_line, last_r} = List.last(rounded)
          List.replace_at(rounded, length(rounded) - 1, {last_line, last_r + diff})
        else
          rounded
        end

      by_pid = Map.new(rounded, fn {l, r} -> {l.product_id, r} end)
      Enum.map(lines, fn l -> {l, Map.get(by_pid, l.product_id, 0)} end)
    end
  end

  def round_to_money(v), do: v |> Dec.money() |> Dec.or0()
end

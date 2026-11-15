defmodule Botyaga.Stock.Writeoff do
  @moduledoc """
  Изписване на продадени стоки и продукция за месец или към дата.
  Повторно пускане за същия месец подменя записа, не го удвоява.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Journal, Periods, Repo}
  alias Botyaga.Journal.Entry
  alias Botyaga.Stock.{Replay, Rules}

  def post(company_id, sub, params) do
    with {:ok, res} <- run(company_id, params["month"], params["until"]) do
      amt = res.amount
      m = params["month"] || params["until"] || ""

      Enum.each(res.entries, fn entry_id ->
        if entry_id > 0 do
          Audit.record(
            company_id,
            sub,
            "journal",
            entry_id,
            m,
            "create",
            "Осчетоводено изписване на стоки/продукция (#{m}), сума #{amt}",
            "",
            amt,
            nil,
            res
          )
        end
      end)

      {:ok, res}
    end
  end

  def run(company_id, month, until) do
    rules = Rules.load(company_id)

    with {:ok, months} <- months(company_id, month, until),
         :ok <- assert_months(company_id, months),
         {:ok, built} <- Replay.rebuild(company_id, "9999-12-31"),
         :ok <- has_rules(rules, built.sales) do
      warnings = later_months(company_id, months, built.warnings)

      {entries, total, warnings} =
        Enum.reduce(months, {[], 0, warnings}, fn m, {entries, total, warnings} ->
          {id, sum, warnings} = one_month(company_id, m, built.sales, rules, warnings)
          {if(id > 0, do: entries ++ [id], else: entries), total + sum, warnings}
        end)

      {:ok, %{months: months, entries: entries, amount: Dec.money(total), warnings: warnings}}
    end
  end

  def rebuild(company_id, params) do
    until = params |> Map.get("until", "") |> to_string() |> String.trim()
    until = if until == "", do: "9999-12-31", else: until

    if until != "9999-12-31" and not iso?(until) do
      {:error, {422, "датата е YYYY-MM-DD"}}
    else
      with {:ok, out} <- Replay.rebuild(company_id, until) do
        {:ok, %{warnings: out.warnings, balances: length(out.balances)}}
      end
    end
  end

  ## Вътрешни

  defp months(company_id, month, until) do
    month = month |> to_string() |> String.trim()
    until = until |> to_string() |> String.trim()

    cond do
      month != "" and until != "" -> {:error, {422, "подайте или месец, или дата"}}
      ym?(month) -> {:ok, [month]}
      not iso?(until) -> {:error, {422, "месецът е YYYY-MM или датата е YYYY-MM-DD"}}
      true -> month_range(company_id, until)
    end
  end

  defp month_range(company_id, until) do
    start_month = fy_month(company_id)
    sm = if start_month in 1..12, do: start_month, else: 1
    y = until |> String.slice(0, 4) |> to_int(2026)
    m = until |> String.slice(5, 2) |> to_int(1)
    year = if m >= sm, do: y, else: y - 1

    Stream.iterate({year, sm}, fn {cy, cm} -> if cm == 12, do: {cy + 1, 1}, else: {cy, cm + 1} end)
    |> Enum.take_while(fn {cy, cm} -> {cy, cm} <= {y, m} end)
    |> Enum.take(24)
    |> Enum.map(fn {cy, cm} -> "#{cy}-#{pad2(cm)}" end)
    |> then(&{:ok, &1})
  end

  defp fy_month(company_id) do
    case Companies.get_company(company_id) do
      nil -> 1
      company -> company.fiscal_year_start_month
    end
  end

  defp assert_months(company_id, months) do
    Enum.reduce_while(months, :ok, fn m, _acc ->
      case Periods.assert_open(company_id, "#{m}-01") do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp has_rules(rules, sales) do
    if rules == [] and not Enum.any?(sales, &(&1.expense_account_id > 0)) do
      {:error, {422, "няма правила за склада — добавете ги в настройки, таб Склад"}}
    else
      :ok
    end
  end

  defp later_months(company_id, months, warnings) do
    last = List.last(months) || ""

    Repo.all(
      from(e in Entry,
        where: e.company_id == ^company_id and e.document_type == "stock_writeoff",
        select: e.document_number
      )
    )
    |> Enum.uniq()
    |> Enum.reduce(warnings, fn n, acc ->
      if n > last,
        do: acc ++ ["има изписване за #{n} след този период — пуснете и него"],
        else: acc
    end)
  end

  defp one_month(company_id, month, sales, rules, warnings) do
    by =
      sales
      |> Enum.filter(fn hit -> String.starts_with?(hit.date, month) and hit.cost != 0 end)
      |> Enum.reduce(%{}, fn hit, acc ->
        Map.update(
          acc,
          hit.product_id,
          {hit.product_name, hit.cost, hit.inventory_account_id, hit.revenue_account_id,
           hit.expense_account_id},
          fn {name, cost, inv, rev, exp} ->
            {name, cost + hit.cost, inv, rev, exp}
          end
        )
      end)

    {sides, total, warnings} =
      Enum.reduce(by, {[], 0, warnings}, fn {_pid, {name, cost, inventory, revenue, expense}},
                                            {sides, total, warnings} ->
        {debit_id, credit_id} =
          if expense > 0 do
            {expense, inventory}
          else
            case Rules.pair(rules, "goods", inventory, revenue) ||
                   Rules.pair(rules, "production", inventory, revenue) do
              nil -> {nil, nil}
              rule -> {rule.offset_account_id, rule.inventory_account_id}
            end
          end

        if debit_id do
          with {:ok, debit} <- account_by_id(debit_id, company_id),
               {:ok, credit} <- account_by_id(credit_id, company_id) do
            amount = Dec.money(cost)

            {sides ++
               [
                 %{account: debit, direction: "debit", amount: amount},
                 %{account: credit, direction: "credit", amount: amount}
               ], total + cost, warnings}
          else
            _ -> {sides, total, warnings}
          end
        else
          {sides, total, warnings ++ ["няма правило за #{name}"]}
        end
      end)

    old =
      Repo.all(
        from(e in Entry,
          where:
            e.company_id == ^company_id and e.document_type == "stock_writeoff" and
              e.document_number == ^month,
          select: e.id
        )
      )

    Enum.each(old, &Journal.wipe/1)

    if sides == [] do
      {0, 0, warnings}
    else
      id_num = month |> String.replace("-", "") |> to_int(0)

      {:ok, entry} =
        Journal.write_entry(
          company_id,
          "#{month}-01",
          "stock_writeoff",
          id_num,
          month,
          "Изписване #{month}",
          0,
          "",
          month,
          sides
        )

      {entry, total, warnings}
    end
  end

  defp account_by_id(id, company_id) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company_id) do
      nil -> {:error, {422, "липсва сметка с id #{id}"}}
      account -> {:ok, account}
    end
  end

  defp ym?(s),
    do:
      String.length(s) == 7 and String.at(s, 4) == "-" and
        String.match?(s, ~r/^[0-9]{4}-[0-9]{2}$/)

  defp iso?(s), do: String.length(s) == 10 and String.match?(s, ~r/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)

  defp to_int(value, default) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end

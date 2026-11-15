defmodule Botyaga.Closing do
  @moduledoc """
  Приключвателни операции в края на месеца. Картата `closing_map` в настройките
  на фирмата казва коя сметка/подсметка към коя се приключва; най-дългият
  префикс печели. Без карта: 60 → 611. Записът е една балансирана статия
  `document_type = 'closing'` на последния ден на месеца.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Journal, Params, Periods, Repo}
  alias Botyaga.Journal.Entry

  @closing_type "closing"

  def closing_type, do: @closing_type

  def parse_rules(settings_raw) do
    rules =
      case Jason.decode(settings_raw || "") do
        {:ok, %{"closing_map" => map}} when is_list(map) ->
          Enum.map(map, fn item ->
            %{
              source: String.trim(item["source"] || ""),
              target: String.trim(item["target"] || "")
            }
          end)

        {:ok, %{"closing_map" => map}} when is_map(map) ->
          Enum.map(map, fn {source, target} ->
            %{source: String.trim(source), target: String.trim(to_string(target))}
          end)

        _ ->
          []
      end

    rules
    |> Enum.reject(&(&1.source == "" or &1.target == ""))
    |> Enum.sort_by(&String.length(&1.source), :desc)
  end

  def default_rules, do: [%{source: "60", target: "611"}]

  def match_rule(rules, number) do
    Enum.find(rules, fn rule -> String.starts_with?(number, rule.source) end)
  end

  def company_rules(company_id) do
    raw =
      case Companies.get_company(company_id) do
        nil -> ""
        company -> company.settings || ""
      end

    has_key? =
      case Jason.decode(raw) do
        {:ok, map} -> Map.has_key?(map, "closing_map")
        _ -> false
      end

    if has_key?, do: parse_rules(raw), else: default_rules()
  end

  def preview(company_id, params) do
    with {:ok, year, month} <- req_month(params),
         {:ok, last_day, period, plans, total} <- compute(company_id, year, month) do
      existing = existing_closing(company_id, year, month)

      body =
        plans
        |> plans_json(total)
        |> Map.merge(%{
          year: year,
          month: month,
          entry_date: last_day,
          period: period,
          document_number: "CLOSE-#{period}",
          already_done: existing != nil
        })

      body =
        case existing do
          {id, number} ->
            Map.merge(body, %{existing_entry_id: id, existing_document_number: number})

          nil ->
            body
        end

      {:ok, body}
    end
  end

  def run(company_id, sub, params) do
    with {:ok, year, month} <- req_month(params),
         {:ok, last_day, period, plans, _total} <- compute(company_id, year, month),
         :ok <- Periods.assert_open(company_id, last_day),
         :ok <- not_done(company_id, year, month, period),
         :ok <- not_empty(plans, period) do
      {sides, total} = plan_lines(plans)
      doc_number = "CLOSE-#{period}"
      desc = "Приключвателни операции за #{period}"

      {:ok, entry_id} =
        Journal.write_entry(
          company_id,
          last_day,
          @closing_type,
          0,
          doc_number,
          desc,
          0,
          "",
          period,
          sides
        )

      out =
        plans
        |> plans_json(total)
        |> Map.merge(%{
          year: year,
          month: month,
          entry_date: last_day,
          period: period,
          document_number: doc_number,
          entry_id: entry_id
        })

      Audit.record(
        company_id,
        sub,
        "journal",
        entry_id,
        doc_number,
        "create",
        "Приключвателни операции за #{period}: #{length(plans)} сметки, оборот #{Dec.money(total)}",
        "",
        Dec.money(total),
        nil,
        out
      )

      {:ok, out}
    end
  end

  ## Вътрешни

  defp compute(company_id, year, month) do
    with {:ok, _first, _next, last_day} <- month_bounds(year, month) do
      rules = company_rules(company_id)

      accounts =
        Repo.all(
          from(a in Catalog.Account,
            where: a.company_id == ^company_id,
            order_by: [asc: a.number, asc: a.id]
          )
        )

      balances = balances_until(company_id, last_day)

      with {:ok, plans} <- build_plans(accounts, balances, rules) do
        {_sides, total} = plan_lines(plans)
        {:ok, last_day, "#{year}-#{pad2(month)}", plans, total}
      end
    end
  end

  defp month_bounds(year, month) do
    if month not in 1..12 do
      {:error, {422, "month трябва да е 1–12"}}
    else
      with {:ok, first} <- Date.new(year, month, 1),
           {ny, nm} = if(month == 12, do: {year + 1, 1}, else: {year, month + 1}),
           {:ok, next} <- Date.new(ny, nm, 1) do
        last = Date.add(next, -1)
        {:ok, Date.to_iso8601(first), Date.to_iso8601(next), Date.to_iso8601(last)}
      else
        _ -> {:error, {422, "невалиден месец"}}
      end
    end
  end

  defp balances_until(company_id, last_day) do
    rows =
      Repo.all(
        from(l in Journal.Line,
          join: e in Entry,
          on: e.id == l.entry_id,
          where: e.company_id == ^company_id and e.entry_date <= ^last_day,
          order_by: [asc: l.id],
          select: {l.account_id, l.direction, l.amount}
        )
      )

    Enum.reduce(rows, %{}, fn {account_id, direction, amount}, acc ->
      value = Dec.or0(amount)
      delta = if direction == "debit", do: value, else: -value
      Map.update(acc, account_id, delta, &(&1 + delta))
    end)
  end

  def build_plans(accounts, balances, rules) do
    targets = MapSet.new(rules, & &1.target)
    by_number = Map.new(accounts, &{&1.number, &1})

    missing =
      Enum.find(rules, fn rule -> not Map.has_key?(by_number, rule.target) end)

    if missing do
      {:error,
       {422,
        "целева сметка #{missing.target} от правило #{missing.source} не съществува в сметкоплана"}}
    else
      plans =
        accounts
        |> Enum.reduce([], fn acc, acc_plans ->
          balance = Map.get(balances, acc.id, 0)

          cond do
            balance == 0 ->
              acc_plans

            MapSet.member?(targets, acc.number) ->
              acc_plans

            true ->
              case match_rule(rules, acc.number) do
                nil ->
                  acc_plans

                rule ->
                  case Map.get(by_number, rule.target) do
                    nil -> acc_plans
                    target -> acc_plans ++ [%{source: acc, target: target, balance: balance}]
                  end
              end
          end
        end)
        |> Enum.sort_by(& &1.source.number)

      {:ok, plans}
    end
  end

  def plan_lines(plans) do
    {sides, totals, total} =
      Enum.reduce(plans, {[], %{}, 0}, fn plan, {sides, totals, total} ->
        total = total + Dec.abs(plan.balance)
        amount = Dec.money(Dec.abs(plan.balance))
        direction = if plan.balance > 0, do: "credit", else: "debit"
        sides = sides ++ [%{account: plan.source, direction: direction, amount: amount}]

        totals =
          Map.update(totals, plan.target.id, {plan.target, plan.balance}, fn {acc, sum} ->
            {acc, sum + plan.balance}
          end)

        {sides, totals, total}
      end)

    target_sides =
      totals
      |> Enum.sort_by(fn {id, _} -> id end)
      |> Enum.reduce([], fn {_id, {acct, signed}}, acc ->
        if signed == 0 do
          acc
        else
          direction = if signed > 0, do: "debit", else: "credit"
          acc ++ [%{account: acct, direction: direction, amount: Dec.money(Dec.abs(signed))}]
        end
      end)

    {sides ++ target_sides, total}
  end

  defp plans_json(plans, total) do
    %{
      lines:
        Enum.map(plans, fn plan ->
          %{
            source_number: plan.source.number,
            source_name: plan.source.name,
            target_number: plan.target.number,
            target_name: plan.target.name,
            balance: Dec.money(plan.balance)
          }
        end),
      total: Dec.money(total),
      count: length(plans)
    }
  end

  defp existing_closing(company_id, year, month) do
    period = "#{year}-#{pad2(month)}"

    case Repo.one(
           from(e in Entry,
             where:
               e.company_id == ^company_id and e.document_type == ^@closing_type and
                 e.vat_period == ^period,
             select: {e.id, e.document_number},
             limit: 1
           )
         ) do
      nil -> nil
      {id, number} -> {id, number}
    end
  end

  defp not_done(company_id, year, month, period) do
    case existing_closing(company_id, year, month) do
      nil ->
        :ok

      {id, number} ->
        {:error, {409, "приключването за #{period} вече е записано (#{number}, запис №#{id})"}}
    end
  end

  defp not_empty([], period),
    do: {:error, {422, "няма салда за приключване за #{period} по зададената карта"}}

  defp not_empty(_, _), do: :ok

  defp req_month(params) do
    year = Params.integer(params, "year")
    month = Params.integer(params, "month")

    cond do
      is_nil(year) -> {:error, {422, "year е задължително"}}
      is_nil(month) -> {:error, {422, "month е задължително"}}
      match?({:error, _}, year) -> {:error, {422, "year е невалидна"}}
      match?({:error, _}, month) -> {:error, {422, "month е невалидна"}}
      year < 2000 -> {:error, {422, "year е невалидна"}}
      true -> {:ok, year, month}
    end
  end

  defp pad2(month), do: month |> Integer.to_string() |> String.pad_leading(2, "0")
end

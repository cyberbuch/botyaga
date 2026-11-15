defmodule Botyaga.Reports.Data do
  @moduledoc """
  Общи данни за справките: дневник, салда и обороти. Крайното салдо е начално
  плюс оборот, без нетиране. Контрагентът се филтрира по записа — редът на
  дневника няма counterpart_id. Порт на `reports_data.rs`.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Repo}
  alias Botyaga.Catalog.Account
  alias Botyaga.Companies.Company
  alias Botyaga.Journal.{Entry, Line}
  alias Botyaga.Periods.OpeningBalance

  def money(v), do: Dec.money(v)

  def day_ok(s) when is_binary(s) do
    String.length(s) == 10 and binary_part(s, 4, 1) == "-" and binary_part(s, 7, 1) == "-" and
      Regex.match?(~r/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/, s)
  end

  def day_ok(_), do: false

  def in_range(day, from, to, exclusive_end) do
    cond do
      String.length(day) < 10 or day < from -> false
      exclusive_end -> day < to
      true -> day <= to
    end
  end

  def starts(_number, ""), do: true
  def starts(number, prefix), do: String.starts_with?(number, prefix)

  @doc "Шаблон `411` и `50*` хващат сметка, която започва с този префикс."
  def acc_match(account, pattern) do
    prefix = String.replace_suffix(pattern, "*", "")
    prefix != "" and String.starts_with?(account, prefix)
  end

  def title(kind) do
    case kind do
      "trial_balance" -> "Оборотна ведомост"
      "general_ledger" -> "Главна книга"
      "chronological" -> "Хронологичен журнал"
      "counterpart_trial" -> "Оборотна ведомост по контрагент"
      "counterpart_chrono" -> "Хронологичен журнал по контрагент"
      "correspondence_ledger" -> "Главна книга по кореспонденции"
      "balance_sheet" -> "Счетоводен баланс"
      "income_statement" -> "Отчет за приходите и разходите"
      "cash_flow" -> "Отчет за паричните потоци"
      "equity" -> "Отчет за собствения капитал"
      _ -> "Справка"
    end
  end

  def slug(kind) do
    case kind do
      "trial_balance" -> "oborotna"
      "general_ledger" -> "glavna-kniga"
      "chronological" -> "hronologichen"
      "counterpart_trial" -> "oborotna-kontragent"
      "counterpart_chrono" -> "hronologichen-kontragent"
      "correspondence_ledger" -> "glavna-kniga-korespondencii"
      "balance_sheet" -> "balans"
      "income_statement" -> "opr"
      "cash_flow" -> "parichen-potok"
      "equity" -> "sobstven-kapital"
      "stock" -> "sklad"
      _ -> "spravka"
    end
  end

  def kind_ok(kind) do
    kind in ~w(trial_balance general_ledger chronological counterpart_trial counterpart_chrono
               correspondence_ledger balance_sheet income_statement cash_flow equity stock)
  end

  def fs_statement(kind) do
    case kind do
      "balance_sheet" -> "balance"
      "income_statement" -> "pl"
      "cash_flow" -> "cashflow"
      "equity" -> "equity"
      _ -> nil
    end
  end

  def head(b, kind) do
    %{
      kind: kind,
      from: b.from,
      to: b.to,
      title: title(kind),
      company_name: b.firm_name,
      company_eik: b.firm_eik
    }
  end

  def firm_line(name, eik) do
    case {name == "", eik == ""} do
      {true, true} -> ""
      {false, true} -> name
      {true, false} -> "ЕИК #{eik}"
      {false, false} -> "#{name} — ЕИК #{eik}"
    end
  end

  def load(company_id, from, to, account, cpid) do
    year = from |> String.slice(0, 4) |> to_int()
    firm = Repo.get(Company, company_id)
    firm_name = (firm && firm.name) || ""
    firm_eik = (firm && firm.eik) || ""

    accounts =
      Repo.all(
        from(a in Account,
          where: a.company_id == ^company_id,
          order_by: [asc: a.number, asc: a.id]
        )
      )
      |> Enum.map(&%{id: &1.id, number: &1.number, name: &1.name})

    ids = MapSet.new(accounts, & &1.id)

    entries =
      Repo.all(
        from(e in Entry,
          where: e.company_id == ^company_id,
          order_by: [asc: e.entry_date, asc: e.id]
        )
      )
      |> Enum.map(
        &%{
          id: &1.id,
          day: String.slice(&1.entry_date || "", 0, 10),
          doc: &1.document_number || "",
          desc: &1.description || "",
          cp_id: &1.counterpart_id || 0,
          cp_name: &1.counterpart_name || ""
        }
      )

    entry_ids = MapSet.new(entries, & &1.id)
    days = Map.new(entries, &{&1.id, &1.day})
    cps = Map.new(entries, &{&1.id, &1.cp_id})

    lines =
      Repo.all(from(l in Line, order_by: [asc: l.id]))
      |> Enum.filter(&MapSet.member?(entry_ids, &1.entry_id))
      |> Enum.map(
        &%{
          entry_id: &1.entry_id,
          account_id: &1.account_id,
          debit: &1.direction == "debit",
          amount: Dec.or0(&1.amount)
        }
      )

    openings =
      Repo.all(
        from(o in OpeningBalance,
          where: o.company_id == ^company_id and o.fiscal_year == ^year,
          order_by: [asc: o.id]
        )
      )
      |> Enum.filter(&MapSet.member?(ids, &1.account_id))
      |> Enum.map(
        &%{
          account_id: &1.account_id,
          cp_id: &1.counterpart_id || 0,
          debit: Dec.or0(&1.debit),
          credit: Dec.or0(&1.credit)
        }
      )

    %{
      company_id: company_id,
      accounts: accounts,
      entries: entries,
      lines: lines,
      openings: openings,
      days: days,
      cps: cps,
      from: from,
      to: to,
      fiscal: "#{pad4(year)}-01-01",
      account: account,
      cpid: cpid,
      firm_name: firm_name,
      firm_eik: firm_eik
    }
  end

  defp to_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp pad4(year), do: year |> Integer.to_string() |> String.pad_leading(4, "0")

  defp add(map, _key, 0), do: map
  defp add(map, key, amount), do: Map.update(map, key, amount, &(&1 + amount))

  def get(map, key), do: Map.get(map, key, 0)

  def turns(b) do
    t = %{od: %{}, oc: %{}, td: %{}, tc: %{}}

    t =
      Enum.reduce(b.openings, t, fn row, t ->
        if b.cpid > 0 and row.cp_id != b.cpid do
          t
        else
          %{
            t
            | od: add(t.od, row.account_id, row.debit),
              oc: add(t.oc, row.account_id, row.credit)
          }
        end
      end)

    from_is_fiscal = b.from == b.fiscal

    Enum.reduce(b.lines, t, fn line, t ->
      if b.cpid > 0 and Map.get(b.cps, line.entry_id, 0) != b.cpid do
        t
      else
        day = Map.get(b.days, line.entry_id, "")

        t =
          if not from_is_fiscal and in_range(day, b.fiscal, b.from, true) do
            if line.debit,
              do: %{t | od: add(t.od, line.account_id, line.amount)},
              else: %{t | oc: add(t.oc, line.account_id, line.amount)}
          else
            t
          end

        if in_range(day, b.from, b.to, false) do
          if line.debit,
            do: %{t | td: add(t.td, line.account_id, line.amount)},
            else: %{t | tc: add(t.tc, line.account_id, line.amount)}
        else
          t
        end
      end
    end)
  end

  def numbers(b), do: Map.new(b.accounts, &{&1.id, &1.number})
  def names(b), do: Map.new(b.accounts, &{&1.number, &1.name})

  @doc "Салда и обороти по номер. Повтарящ се номер се събира. Връща [od, oc, td, tc]."
  def by_number(b, t) do
    nums = numbers(b)

    Enum.map([t.od, t.oc, t.td, t.tc], fn map ->
      Enum.reduce(map, %{}, fn {id, amount}, acc ->
        case Map.fetch(nums, id) do
          {:ok, num} -> Map.update(acc, num, amount, &(&1 + amount))
          :error -> acc
        end
      end)
    end)
  end

  @doc "FIFO двойки дебит/кредит, както в хронологичния журнал."
  def pair(debits, credits), do: pair(debits, credits, [])

  defp pair([], _credits, acc), do: Enum.reverse(acc)
  defp pair(_debits, [], acc), do: Enum.reverse(acc)

  defp pair([d | dr], [c | cr], acc) do
    cond do
      d.rem == 0 ->
        pair(dr, [c | cr], acc)

      c.rem == 0 ->
        pair([d | dr], cr, acc)

      true ->
        amount = min(d.rem, c.rem)
        d = %{d | rem: d.rem - amount}
        c = %{c | rem: c.rem - amount}
        pair([d | dr], [c | cr], [{d.num, c.num, amount} | acc])
    end
  end

  def correspondences(b) do
    nums = numbers(b)
    by_entry = Enum.group_by(b.lines, & &1.entry_id)

    Enum.reduce(b.entries, %{}, fn entry, pairs ->
      if not in_range(entry.day, b.from, b.to, false) do
        pairs
      else
        lines = Map.get(by_entry, entry.id, [])

        {debits, credits} =
          Enum.reduce(lines, {[], []}, fn line, {d, c} ->
            side = %{num: Map.get(nums, line.account_id, ""), rem: line.amount}
            if line.debit, do: {d ++ [side], c}, else: {d, c ++ [side]}
          end)

        Enum.reduce(pair(debits, credits), pairs, fn
          {_d, _c, 0}, acc ->
            acc

          {d, c, amount}, acc ->
            Map.update(acc, {d, c}, amount, &(&1 + amount))
        end)
      end
    end)
  end
end

defmodule Botyaga.DbCheck do
  @moduledoc """
  Проверка на интегритета на базата от „Глобални настройки“. Връзката, основните
  таблици, сираци по фирма/документ и балансът на статиите (дебит = кредит).
  Порт на `db_check.rs`, с COUNT заявки вместо четене в паметта (Postgres).
  """

  alias Botyaga.{Dec, Repo}

  @tables ~w(companies accounts counterparts products invoices invoice_lines journal_entries
             journal_lines users roles user_companies bank_accounts bank_transactions fixed_assets
             material_issues internal_docs production_orders recipes dividends opening_balances
             accounting_periods audit_logs document_series settings)

  def integrity do
    started = System.monotonic_time(:millisecond)

    {tables, table_errors} =
      Enum.reduce(@tables, {[], []}, fn name, {tables, errors} ->
        case count("SELECT COUNT(*) FROM #{name}") do
          {:ok, n} -> {tables ++ [%{name: name, rows: n}], errors}
          {:error, e} -> {tables, errors ++ ["#{name}: #{e}"]}
        end
      end)

    tables_ok = table_errors == []

    checks = [
      check("connection", true, ""),
      check(
        "tables",
        tables_ok,
        if(tables_ok,
          do: "#{length(tables)}/#{length(@tables)}",
          else: Enum.join(table_errors, "; ")
        )
      )
    ]

    checks =
      checks ++
        [
          orphan("orphan_invoices", "invoices"),
          orphan("orphan_journal_entries", "journal_entries"),
          orphan("orphan_accounts", "accounts"),
          orphan("orphan_products", "products"),
          dangling("orphan_invoice_lines", "invoice_lines", "invoice_id", "invoices"),
          dangling("orphan_journal_lines", "journal_lines", "entry_id", "journal_entries"),
          journal_balance()
        ]

    ok = Enum.all?(checks, & &1.ok)

    %{
      ok: ok,
      checked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      duration_ms: System.monotonic_time(:millisecond) - started,
      checks: checks,
      tables: tables
    }
  end

  defp check(id, ok, detail), do: %{id: id, ok: ok, detail: detail}

  defp count(sql) do
    {:ok, hd(hd(Repo.query!(sql).rows))}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp orphan(id, table) do
    sql =
      "SELECT COUNT(*) FROM #{table} t WHERE NOT EXISTS " <>
        "(SELECT 1 FROM companies c WHERE c.id = t.company_id)"

    case count(sql) do
      {:ok, n} -> check(id, n == 0, Integer.to_string(n))
      {:error, e} -> check(id, false, e)
    end
  end

  defp dangling(id, table, fk, parent) do
    sql =
      "SELECT COUNT(*) FROM #{table} t WHERE NOT EXISTS " <>
        "(SELECT 1 FROM #{parent} p WHERE p.id = t.#{fk})"

    case count(sql) do
      {:ok, n} -> check(id, n == 0, Integer.to_string(n))
      {:error, e} -> check(id, false, e)
    end
  end

  defp journal_balance do
    rows = Repo.query!("SELECT entry_id, direction, amount FROM journal_lines").rows

    {debit, credit} =
      Enum.reduce(rows, {%{}, %{}}, fn [entry, direction, amount], {d, c} ->
        is_debit = direction |> String.trim() |> String.downcase() |> String.starts_with?("d")
        v = Dec.or0(amount)

        if is_debit,
          do: {Map.update(d, entry, v, &(&1 + v)), c},
          else: {d, Map.update(c, entry, v, &(&1 + v))}
      end)

    keys = Map.keys(debit) ++ Map.keys(credit)

    bad =
      keys
      |> Enum.uniq()
      |> Enum.count(fn e -> Map.get(debit, e, 0) != Map.get(credit, e, 0) end)

    check("journal_balance", bad == 0, Integer.to_string(bad))
  rescue
    e -> check("journal_balance", false, Exception.message(e))
  end
end

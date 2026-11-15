defmodule Botyaga.Reports.Book do
  @moduledoc "Хронологичен журнал (FIFO двойки) и главна книга. Порт на `reports_book.rs`."

  alias Botyaga.Reports.Data

  defp grouped(b), do: Enum.group_by(b.lines, & &1.entry_id)

  def chrono(kind, b) do
    nums = Data.numbers(b)
    groups = grouped(b)

    header = [
      [Data.title(kind)],
      ["#{b.from} — #{b.to}"],
      [
        "№",
        "Дата",
        "Документ",
        "Описание",
        "Контрагент",
        "Дт сметка",
        "Кт сметка",
        "Дебит",
        "Кредит"
      ]
    ]

    {rows, grid_rows, td, tc, _n} =
      Enum.reduce(b.entries, {[], [], 0, 0, 1}, fn entry, {rows, grid, td, tc, n} ->
        cond do
          not Data.in_range(entry.day, b.from, b.to, false) ->
            {rows, grid, td, tc, n}

          b.cpid > 0 and entry.cp_id != b.cpid ->
            {rows, grid, td, tc, n}

          true ->
            lines = Map.get(groups, entry.id)

            if lines == nil do
              {rows, grid, td, tc, n}
            else
              {debits, credits, acc_ok} =
                Enum.reduce(lines, {[], [], b.account == ""}, fn line, {d, c, ok} ->
                  num = Map.get(nums, line.account_id, "")
                  ok = ok or Data.starts(num, b.account)
                  side = %{num: num, rem: line.amount}
                  if line.debit, do: {d ++ [side], c, ok}, else: {d, c ++ [side], ok}
                end)

              if not acc_ok do
                {rows, grid, td, tc, n}
              else
                Enum.reduce(Data.pair(debits, credits), {rows, grid, td, tc, n}, fn
                  {_da, _ca, 0}, acc ->
                    acc

                  {da, ca, amount}, {rows, grid, td, tc, n} ->
                    row = %{
                      row_number: n,
                      date: entry.day,
                      document_number: entry.doc,
                      description: entry.desc,
                      counterpart_name: entry.cp_name,
                      debit_account: da,
                      credit_account: ca,
                      debit_amount: Data.money(amount),
                      credit_amount: Data.money(amount)
                    }

                    grid_row = [
                      Integer.to_string(n),
                      entry.day,
                      entry.doc,
                      entry.desc,
                      entry.cp_name,
                      da,
                      ca,
                      Data.money(amount),
                      Data.money(amount)
                    ]

                    {rows ++ [row], grid ++ [grid_row], td + amount, tc + amount, n + 1}
                end)
              end
            end
        end
      end)

    grid =
      header ++
        grid_rows ++
        [["", "", "", "Общо", "", "", "", Data.money(td), Data.money(tc)]]

    body =
      b
      |> Data.head(kind)
      |> Map.put(:rows, rows)
      |> Map.put(:totals, %{debit_amount: Data.money(td), credit_amount: Data.money(tc)})

    %{body: body, slug: Data.slug(kind), grid: grid}
  end

  def ledger(kind, b) do
    t = Data.turns(b)
    groups = grouped(b)

    header = [
      [Data.title(kind)],
      ["#{b.from} — #{b.to}"],
      ["Сметка", "Дата", "Документ", "Описание", "Дебит", "Кредит"]
    ]

    {accounts, grid_rows} =
      Enum.reduce(b.accounts, {[], []}, fn acc, {accounts, grid} ->
        if not Data.starts(acc.number, b.account) do
          {accounts, grid}
        else
          od = Data.get(t.od, acc.id)
          oc = Data.get(t.oc, acc.id)
          td = Data.get(t.td, acc.id)
          tc = Data.get(t.tc, acc.id)

          if od == 0 and oc == 0 and td == 0 and tc == 0 do
            {accounts, grid}
          else
            cd = od + td
            cc = oc + tc
            label = "#{acc.number} #{acc.name}"
            grid = grid ++ [[label, "", "", "Начално салдо", Data.money(od), Data.money(oc)]]

            {txs, grid, _net} =
              Enum.reduce(b.entries, {[], grid, od - oc}, fn entry, {txs, grid, net} ->
                if not Data.in_range(entry.day, b.from, b.to, false) do
                  {txs, grid, net}
                else
                  lines = Map.get(groups, entry.id, [])

                  Enum.reduce(lines, {txs, grid, net}, fn line, {txs, grid, net} ->
                    cond do
                      line.account_id != acc.id ->
                        {txs, grid, net}

                      b.cpid > 0 and entry.cp_id != b.cpid ->
                        {txs, grid, net}

                      true ->
                        {d, c, net} =
                          if line.debit do
                            {line.amount, 0, net + line.amount}
                          else
                            {0, line.amount, net - line.amount}
                          end

                        {rd, rc} =
                          cond do
                            net > 0 -> {net, 0}
                            net < 0 -> {0, -net}
                            true -> {0, 0}
                          end

                        tx = %{
                          date: entry.day,
                          document_number: entry.doc,
                          description: entry.desc,
                          debit: Data.money(d),
                          credit: Data.money(c),
                          running_debit: Data.money(rd),
                          running_credit: Data.money(rc)
                        }

                        grid_row = [
                          "",
                          entry.day,
                          entry.doc,
                          entry.desc,
                          Data.money(d),
                          Data.money(c)
                        ]

                        {txs ++ [tx], grid ++ [grid_row], net}
                    end
                  end)
                end
              end)

            grid =
              grid ++
                [
                  ["", "", "", "Обороти за периода", Data.money(td), Data.money(tc)],
                  ["", "", "", "Крайно салдо", Data.money(cd), Data.money(cc)]
                ]

            account = %{
              account_number: acc.number,
              account_name: acc.name,
              opening_debit: Data.money(od),
              opening_credit: Data.money(oc),
              turnover_debit: Data.money(td),
              turnover_credit: Data.money(tc),
              closing_debit: Data.money(cd),
              closing_credit: Data.money(cc),
              transactions: txs
            }

            {accounts ++ [account], grid}
          end
        end
      end)

    body = b |> Data.head(kind) |> Map.put(:accounts, accounts)
    %{body: body, slug: Data.slug(kind), grid: header ++ grid_rows}
  end
end

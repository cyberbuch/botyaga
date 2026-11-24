defmodule Botyaga.Reports.Trial do
  @moduledoc "Шестколонна оборотна ведомост, и същата по контрагент. Порт на `reports_trial.rs`."

  alias Botyaga.Reports.Data

  def build(kind, b) do
    cond do
      # Избрана сметка или всички контрагенти: сметката е отгоре, под нея нейните контрагенти.
      b.account != "" -> build_by_cp(kind, b)
      kind == "counterpart_trial" and b.cpid == 0 -> build_by_cp(kind, b)
      true -> build_accounts(kind, b)
    end
  end

  # Филтър по сметка: за всяка съвпадаща сметка — всичките ѝ контрагенти.
  defp build_by_cp(kind, b) do
    t = Data.turns_by_cp(b)
    names = Data.cp_names(b)
    by_acc = Enum.group_by(t, fn {{acc_id, _cp}, _s} -> acc_id end)

    pairs =
      b.accounts
      |> Enum.filter(&Data.starts(&1.number, b.account))
      |> Enum.flat_map(fn acc ->
        Enum.sort_by(Map.get(by_acc, acc.id, []), fn {{_a, cp}, _s} -> cp end)
        |> Enum.map(fn {{_a, cp}, sums} -> {acc, cp, sums} end)
      end)

    header = [
      [
        if(b.account != "",
          do: Data.title(kind) <> " по сметка #{b.account}",
          else: Data.title(kind)
        )
      ],
      ["#{b.from} — #{b.to}"],
      ["Сметка", "Наименование", "Контрагент", "НД", "НК", "ОД", "ОК", "КД", "КК"]
    ]

    {rows, grid_rows, totals} =
      Enum.reduce(pairs, {[], [], zero()}, fn {acc, cp, s}, {rows, grid, tot} ->
        if s.od == 0 and s.oc == 0 and s.td == 0 and s.tc == 0 do
          {rows, grid, tot}
        else
          cd = s.od + s.td
          cc = s.oc + s.tc
          cp_name = Map.get(names, cp, "") |> then(&if(&1 == "", do: "—", else: &1))

          row = %{
            account_number: acc.number,
            account_name: acc.name,
            counterpart_name: cp_name,
            opening_debit: Data.money(s.od),
            opening_credit: Data.money(s.oc),
            turnover_debit: Data.money(s.td),
            turnover_credit: Data.money(s.tc),
            closing_debit: Data.money(cd),
            closing_credit: Data.money(cc)
          }

          grid_row = [
            acc.number,
            acc.name,
            cp_name,
            Data.money(s.od),
            Data.money(s.oc),
            Data.money(s.td),
            Data.money(s.tc),
            Data.money(cd),
            Data.money(cc)
          ]

          {rows ++ [row], grid ++ [grid_row], add_totals(tot, s.od, s.oc, s.td, s.tc, cd, cc)}
        end
      end)

    grid =
      header ++
        grid_rows ++
        [
          [
            "",
            "Общо",
            "",
            Data.money(totals.od),
            Data.money(totals.oc),
            Data.money(totals.td),
            Data.money(totals.tc),
            Data.money(totals.cd),
            Data.money(totals.cc)
          ]
        ]

    body =
      b
      |> Data.head(kind)
      |> Map.put(:mode, "by_account_cp")
      |> Map.put(:rows, rows)
      |> Map.put(:totals, totals_body(totals))

    %{body: body, slug: Data.slug(kind), grid: grid}
  end

  defp add_totals(tot, od, oc, td, tc, cd, cc) do
    %{
      tot
      | od: tot.od + od,
        oc: tot.oc + oc,
        td: tot.td + td,
        tc: tot.tc + tc,
        cd: tot.cd + cd,
        cc: tot.cc + cc
    }
  end

  defp totals_body(tot) do
    %{
      opening_debit: Data.money(tot.od),
      opening_credit: Data.money(tot.oc),
      turnover_debit: Data.money(tot.td),
      turnover_credit: Data.money(tot.tc),
      closing_debit: Data.money(tot.cd),
      closing_credit: Data.money(tot.cc)
    }
  end

  defp build_accounts(kind, b) do
    t = Data.turns(b)

    header = [
      [Data.title(kind)],
      ["#{b.from} — #{b.to}"],
      ["Сметка", "Наименование", "НД", "НК", "ОД", "ОК", "КД", "КК"]
    ]

    {rows, grid_rows, totals} =
      Enum.reduce(b.accounts, {[], [], zero()}, fn acc, {rows, grid, tot} ->
        if not Data.starts(acc.number, b.account) do
          {rows, grid, tot}
        else
          od = Data.get(t.od, acc.id)
          oc = Data.get(t.oc, acc.id)
          td = Data.get(t.td, acc.id)
          tc = Data.get(t.tc, acc.id)

          if od == 0 and oc == 0 and td == 0 and tc == 0 do
            {rows, grid, tot}
          else
            cd = od + td
            cc = oc + tc

            row = %{
              account_number: acc.number,
              account_name: acc.name,
              opening_debit: Data.money(od),
              opening_credit: Data.money(oc),
              turnover_debit: Data.money(td),
              turnover_credit: Data.money(tc),
              closing_debit: Data.money(cd),
              closing_credit: Data.money(cc)
            }

            grid_row = [
              acc.number,
              acc.name,
              Data.money(od),
              Data.money(oc),
              Data.money(td),
              Data.money(tc),
              Data.money(cd),
              Data.money(cc)
            ]

            tot = %{
              od: tot.od + od,
              oc: tot.oc + oc,
              td: tot.td + td,
              tc: tot.tc + tc,
              cd: tot.cd + cd,
              cc: tot.cc + cc
            }

            {rows ++ [row], grid ++ [grid_row], tot}
          end
        end
      end)

    grid =
      header ++
        grid_rows ++
        [
          [
            "",
            "Общо",
            Data.money(totals.od),
            Data.money(totals.oc),
            Data.money(totals.td),
            Data.money(totals.tc),
            Data.money(totals.cd),
            Data.money(totals.cc)
          ]
        ]

    body =
      b
      |> Data.head(kind)
      |> Map.put(:mode, "accounts")
      |> Map.put(:rows, rows)
      |> Map.put(:totals, totals_body(totals))

    %{body: body, slug: Data.slug(kind), grid: grid}
  end

  defp zero, do: %{od: 0, oc: 0, td: 0, tc: 0, cd: 0, cc: 0}
end

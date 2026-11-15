defmodule Botyaga.Reports.Trial do
  @moduledoc "Шестколонна оборотна ведомост, и същата по контрагент. Порт на `reports_trial.rs`."

  alias Botyaga.Reports.Data

  def build(kind, b) do
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
      |> Map.put(:rows, rows)
      |> Map.put(:totals, %{
        opening_debit: Data.money(totals.od),
        opening_credit: Data.money(totals.oc),
        turnover_debit: Data.money(totals.td),
        turnover_credit: Data.money(totals.tc),
        closing_debit: Data.money(totals.cd),
        closing_credit: Data.money(totals.cc)
      })

    %{body: body, slug: Data.slug(kind), grid: grid}
  end

  defp zero, do: %{od: 0, oc: 0, td: 0, tc: 0, cd: 0, cc: 0}
end

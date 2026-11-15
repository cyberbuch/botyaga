defmodule Botyaga.Reports.Corr do
  @moduledoc "Главна книга по кореспонденции: водещ дебит и водещ кредит. Порт на `reports_corr.rs`."

  alias Botyaga.Reports.Data

  def build(kind, b) do
    t = Data.turns(b)
    pairs = Data.correspondences(b)
    names = Data.names(b)

    header = [
      [Data.title(kind)],
      ["#{b.from} — #{b.to}"],
      ["Сметка", "Кореспонденция", "Дебит", "Кредит"]
    ]

    {debit_lead, debit_grid} = side(b, t, pairs, names, 0)
    {credit_lead, credit_grid} = side(b, t, pairs, names, 1)

    body =
      b
      |> Data.head(kind)
      |> Map.put(:debit_lead, debit_lead)
      |> Map.put(:credit_lead, credit_lead)

    %{body: body, slug: Data.slug(kind), grid: header ++ debit_grid ++ credit_grid}
  end

  defp side(b, t, pairs, names, side) do
    title = if side == 0, do: "Водещ дебит", else: "Водещ кредит"

    {lead, grid} =
      Enum.reduce(b.accounts, {[], [[title, "", "", ""]]}, fn acc, {lead, grid} ->
        if not Data.starts(acc.number, b.account) do
          {lead, grid}
        else
          od = Data.get(t.od, acc.id)
          oc = Data.get(t.oc, acc.id)
          td = Data.get(t.td, acc.id)
          tc = Data.get(t.tc, acc.id)

          if od == 0 and oc == 0 and td == 0 and tc == 0 do
            {lead, grid}
          else
            grid =
              grid ++
                [["#{acc.number} #{acc.name}", "Начално салдо", Data.money(od), Data.money(oc)]]

            {rows, grid} =
              Enum.reduce(b.accounts, {[], grid}, fn other, {rows, grid} ->
                key =
                  if side == 0,
                    do: {acc.number, other.number},
                    else: {other.number, acc.number}

                amount = Map.get(pairs, key)

                if amount == nil or amount == 0 do
                  {rows, grid}
                else
                  {d, c} = if side == 0, do: {amount, 0}, else: {0, amount}
                  cname = Map.get(names, other.number, "")

                  row = %{
                    correspondent: other.number,
                    correspondent_name: cname,
                    debit: Data.money(d),
                    credit: Data.money(c)
                  }

                  lab =
                    if side == 0,
                      do: "Кт #{other.number} #{cname}",
                      else: "Дт #{other.number} #{cname}"

                  {rows ++ [row], grid ++ [["", lab, Data.money(d), Data.money(c)]]}
                end
              end)

            cd = od + td
            cc = oc + tc

            grid =
              grid ++
                [
                  ["", "Обороти за периода", Data.money(td), Data.money(tc)],
                  ["", "Крайно салдо", Data.money(cd), Data.money(cc)]
                ]

            entry = %{
              account_number: acc.number,
              account_name: acc.name,
              opening_debit: Data.money(od),
              opening_credit: Data.money(oc),
              turnover_debit: Data.money(td),
              turnover_credit: Data.money(tc),
              closing_debit: Data.money(cd),
              closing_credit: Data.money(cc),
              rows: rows
            }

            {lead ++ [entry], grid}
          end
        end
      end)

    {lead, grid}
  end
end

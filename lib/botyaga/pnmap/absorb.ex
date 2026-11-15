defmodule Botyaga.Pnmap.Absorb do
  @moduledoc """
  При нерегистрирана по ДДС фирма и входяща фактура разпределя ДДС-то директно в
  стойността на артикулите (net = total, vat_rate = 0), без разлика в стотинките
  спрямо общата сума. Порт на `pnmap.rs#absorb_vat_into_lines` (центовa аритметика).
  """

  alias Botyaga.Dec
  alias Botyaga.Invoicing.Money

  def absorb([], doc_net, doc_vat, doc_total) do
    tot_c = Money.cents(doc_total) || 0
    net_c = Money.cents(doc_net) || 0
    vat_c = Money.cents(doc_vat) || 0
    fin = if tot_c != 0, do: tot_c, else: net_c + vat_c
    m = Money.money(fin)
    {[], m, m}
  end

  def absorb(lines, doc_net, doc_vat, doc_total) do
    {nets, gross} =
      Enum.reduce(lines, {[], []}, fn line, {nets, gross} ->
        {net_c, tot_c} = line_amounts(line)
        {nets ++ [net_c], gross ++ [tot_c]}
      end)

    doc_tot_c = Money.cents(doc_total) || 0
    doc_net_c = Money.cents(doc_net) || 0
    doc_vat_c = Money.cents(doc_vat) || 0
    sum_net = Enum.sum(nets)
    sum_gross = Enum.sum(gross)

    target =
      cond do
        doc_tot_c != 0 -> doc_tot_c
        doc_net_c != 0 or doc_vat_c != 0 -> doc_net_c + doc_vat_c
        true -> sum_gross
      end

    gross =
      if sum_gross == sum_net and target > sum_net and sum_net != 0 do
        spread(nets, gross, target - sum_net, sum_net)
      else
        gross
      end

    sum_gross = Enum.sum(gross)

    gross =
      if target != 0 and sum_gross != target do
        diff = target - sum_gross
        last = List.last(gross)

        if last + diff >= 0,
          do: List.replace_at(gross, length(gross) - 1, last + diff),
          else: gross
      else
        gross
      end

    final_sum = Enum.sum(gross)

    lines =
      lines
      |> Enum.zip(gross)
      |> Enum.map(fn {line, g} -> rewrite(line, g) end)

    fin = Money.money(final_sum)
    {lines, fin, fin}
  end

  defp line_amounts(line) do
    q = Dec.or0(str(line, "quantity"))
    q = if q == 0, do: Dec.scale(), else: q
    up = Dec.or0(str(line, "unit_price"))
    rate_pct = Dec.or0(str(line, "vat_rate"))
    net_s = str(line, "net_amount")
    vat_s = str(line, "vat_amount")
    tot_s = str(line, "total_amount")

    net_c =
      if net_s != "",
        do: Money.cents(net_s) || 0,
        else: Money.cents(Dec.money(Dec.mul(q, up))) || 0

    vat_c =
      cond do
        vat_s != "" ->
          Money.cents(vat_s) || 0

        tot_s != "" and (Money.cents(tot_s) || 0) != 0 and net_c != 0 ->
          (Money.cents(tot_s) || 0) - net_c

        rate_pct > 0 ->
          Kernel.div(net_c * rate_pct + 50_000_000, 100_000_000)

        true ->
          0
      end

    tot_c =
      if tot_s != "" and (Money.cents(tot_s) || 0) != 0,
        do: Money.cents(tot_s) || 0,
        else: net_c + vat_c

    {net_c, tot_c}
  end

  defp spread(nets, gross, extra, sum_net) do
    n = length(gross)
    half = Kernel.div(Kernel.abs(sum_net), 2)

    {gross, _acc} =
      nets
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {net_i, i}, {acc_g, acc} ->
        share =
          if i + 1 == n,
            do: extra - acc,
            else: Kernel.div(extra * net_i + half, sum_net)

        acc = if i + 1 == n, do: acc, else: acc + share
        {acc_g ++ [net_i + share], acc}
      end)

    gross
  end

  defp rewrite(line, g) do
    g_str = Money.money(g)
    q = Dec.or0(str(line, "quantity"))
    g_dec = Dec.or0(g_str)
    up_str = if q > 0, do: Dec.money(Dec.div(g_dec, q) || g_dec), else: g_str

    line
    |> Map.put("unit_price", up_str)
    |> Map.put("vat_rate", "0")
    |> Map.put("net_amount", g_str)
    |> Map.put("vat_amount", "0.00")
    |> Map.put("total_amount", g_str)
  end

  defp str(line, key) do
    case Map.get(line, key) do
      nil -> ""
      v -> v |> to_string() |> String.trim()
    end
  end
end

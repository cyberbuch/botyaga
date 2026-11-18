defmodule Botyaga.Banking.Formats.Mt940 do
  @moduledoc "MT940 (SWIFT) банкови извлечения."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv

  @impl true
  def key, do: "mt940"

  @impl true
  def name, do: "MT940"

  @impl true
  def matches?(content) do
    String.contains?(content, ":20:") or String.contains?(content, ":60F:") or
      String.contains?(content, ":61:")
  end

  @impl true
  def parse(content) do
    {iban, currency, txs, pending} =
      content
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({"", "", [], nil}, fn raw, {iban, currency, txs, pending} ->
        line = String.trim(raw)

        iban =
          case line do
            ":25:" <> rest ->
              t = String.trim(rest)
              if String.starts_with?(t, "BG") or String.starts_with?(t, "LT"), do: t, else: iban

            _ ->
              iban
          end

        currency =
          if String.starts_with?(line, ":60F:"), do: mt_currency(line, currency), else: currency

        cond do
          String.starts_with?(line, ":61:") ->
            txs = if pending, do: txs ++ [pending], else: txs
            rest = String.replace_prefix(line, ":61:", "")
            {iban, currency, txs, mt_line(rest, currency)}

          String.starts_with?(line, ":86:") and pending != nil ->
            extra = line |> String.replace_prefix(":86:", "") |> String.trim()

            desc =
              if extra == "",
                do: pending.description,
                else:
                  if(pending.description == "",
                    do: extra,
                    else: pending.description <> " " <> extra
                  )

            {iban, currency, txs, %{pending | description: desc}}

          true ->
            {iban, currency, txs, pending}
        end
      end)

    txs = if pending, do: txs ++ [pending], else: txs
    currency = if currency == "", do: "EUR", else: currency
    %{format_name: "MT940", account_iban: iban, account_currency: currency, txs: txs}
  end

  defp mt_currency(line, current) do
    chars = String.graphemes(line)

    Enum.find_value(0..(length(chars) - 3), current, fn i ->
      cur = Enum.slice(chars, i, 3) |> Enum.join()
      if String.match?(cur, ~r/^[A-Z]{3}$/) and cur != "F", do: cur
    end)
  end

  defp mt_line(rest, currency) do
    chars = String.graphemes(rest)

    if length(chars) < 7 do
      nil
    else
      date =
        "20#{Enum.slice(chars, 0, 2) |> Enum.join()}-#{Enum.slice(chars, 2, 2) |> Enum.join()}-#{Enum.slice(chars, 4, 2) |> Enum.join()}"

      i =
        if Enum.slice(chars, 6, 4) |> Enum.join() |> String.match?(~r/^[0-9]{4}$/),
          do: 10,
          else: 6

      sign = Enum.at(chars, i)

      if sign in ["C", "D", "c", "d"] do
        {amt, j} = mt_amount(chars, i + 1, "")
        amount = Csv.norm_money(amt)

        if amount in ["", "0.00"] do
          nil
        else
          amount =
            if String.downcase(sign) == "d",
              do: "-" <> String.trim_leading(amount, "-"),
              else: amount

          reference = chars |> Enum.drop(j) |> Enum.join() |> String.trim()

          %{
            date: date,
            amount: amount,
            currency: currency,
            description: "",
            contra_name: "",
            contra_iban: "",
            reference: reference,
            is_duplicate: false
          }
        end
      end
    end
  end

  defp mt_amount(chars, i, acc) do
    case Enum.at(chars, i) do
      nil ->
        {acc, i}

      c ->
        if String.match?(c, ~r/[0-9,.]/) do
          mt_amount(chars, i + 1, acc <> c)
        else
          {acc, i}
        end
    end
  end
end

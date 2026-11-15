defmodule Botyaga.Banking.Csv do
  @moduledoc "CSV и MT940 банкови извлечения; XML форматите са в `Banking.Xml`."

  alias Botyaga.Dec
  alias Botyaga.Banking.Xml

  def detect(content) do
    trimmed = content |> String.trim() |> String.trim_leading("﻿")

    cond do
      String.contains?(trimmed, "<AccountTransactionsHistory") ->
        Xml.parse_postbank_xml(trimmed)

      String.contains?(trimmed, "<AccountMovement>") ->
        Xml.parse_unicredit_xml(trimmed)

      String.contains?(trimmed, "<IBAN_S>") or String.contains?(trimmed, "<POST_DATE>") ->
        Xml.parse_obb_xml(trimmed)

      String.contains?(trimmed, "BkToCstmrStmt") or String.contains?(trimmed, "<Ntry>") or
          String.contains?(trimmed, ":Ntry>") ->
        Xml.parse_camt053(trimmed)

      String.contains?(trimmed, ":20:") or String.contains?(trimmed, ":60F:") or
          String.contains?(trimmed, ":61:") ->
        parse_mt940(trimmed)

      csv?(trimmed) ->
        parse_csv(trimmed)

      true ->
        nil
    end
  end

  defp csv?(trimmed) do
    lower = String.downcase(trimmed)

    (String.contains?(trimmed, ";") or String.contains?(trimmed, ",") or
       String.contains?(trimmed, "|")) and
      (String.contains?(lower, "iban") or String.contains?(lower, "дата") or
         String.contains?(lower, "date"))
  end

  ## CSV

  defp parse_csv(content) do
    delim =
      if String.contains?(content, "|"),
        do: "|",
        else: if(String.contains?(content, ";"), do: ";", else: ",")

    lines = String.split(content, ~r/\r?\n/)

    {iban, currency} = csv_meta(lines)
    header_idx = Enum.find_index(lines, fn line -> csv_header?(line) end)

    txs =
      if header_idx do
        heads =
          lines
          |> Enum.at(header_idx)
          |> String.split(delim)
          |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

        cols = csv_columns(heads)

        lines
        |> Enum.drop(header_idx + 1)
        |> Enum.reduce([], fn line, acc -> csv_row(line, delim, cols, currency, acc) end)
        |> Enum.reverse()
      else
        []
      end

    currency = if currency == "", do: "EUR", else: currency
    %{format_name: "CSV", account_iban: iban, account_currency: currency, txs: txs}
  end

  defp csv_meta(lines) do
    Enum.reduce(lines, {"", ""}, fn line, {iban, currency} ->
      iban =
        if String.contains?(line, "IBAN:") or String.contains?(line, "IBAN;") or
             String.contains?(line, "IBAN,") do
          Enum.find_value(String.split(line, ":"), iban, fn part ->
            t = part |> String.trim() |> String.trim(";") |> String.trim(",")
            if String.starts_with?(t, "BG") or String.starts_with?(t, "LT"), do: t
          end)
        else
          iban
        end

      currency =
        if String.contains?(line, "Валута:") or String.contains?(line, "Currency:") do
          Enum.find_value(String.split(line, ":"), currency, fn part ->
            t = String.trim(part)
            if String.length(t) == 3 and String.match?(t, ~r/^[A-Za-z]{3}$/), do: String.upcase(t)
          end)
        else
          currency
        end

      {iban, currency}
    end)
  end

  defp csv_header?(line) do
    lower = String.downcase(line)
    has_date = String.contains?(lower, "дата") or String.contains?(lower, "date")

    has_amt =
      Enum.any?(
        ["дебит", "кредит", "сума", "amount", "плащания", "постъпления"],
        &String.contains?(lower, &1)
      )

    has_date and has_amt
  end

  defp csv_columns(heads) do
    Enum.with_index(heads)
    |> Enum.reduce(
      %{date: 0, debit: nil, credit: nil, amount: nil, desc: nil, ref: nil, contra: nil},
      fn {h, c}, acc ->
        acc =
          if acc.date == 0 and (String.contains?(h, "дата") or String.contains?(h, "date")),
            do: %{acc | date: c},
            else: acc

        acc =
          if String.contains?(h, "дебит") or String.contains?(h, "debit") or
               String.contains?(h, "плащания"),
             do: %{acc | debit: c},
             else: acc

        acc =
          if String.contains?(h, "кредит") or String.contains?(h, "credit") or
               String.contains?(h, "постъпления"),
             do: %{acc | credit: c},
             else: acc

        acc =
          if String.contains?(h, "сума") or String.contains?(h, "amount"),
            do: %{acc | amount: c},
            else: acc

        acc =
          if is_nil(acc.contra) and
               (String.contains?(h, "кореспондент") or String.contains?(h, "контрагент") or
                  String.contains?(h, "наредител")),
             do: %{acc | contra: c},
             else: acc

        acc =
          if is_nil(acc.desc) and
               (String.contains?(h, "описание") or String.contains?(h, "description") or
                  String.contains?(h, "основание") or String.length(h) > 15),
             do: %{acc | desc: c},
             else: acc

        if is_nil(acc.ref) and
             (String.contains?(h, "референ") or String.contains?(h, "reference") or
                String.contains?(h, "id")),
           do: %{acc | ref: c},
           else: acc
      end
    )
    |> then(fn cols ->
      if is_nil(cols.desc) and heads != [], do: %{cols | desc: length(heads) - 1}, else: cols
    end)
  end

  defp csv_row(line, delim, cols, currency, acc) do
    line = String.trim(line)

    if line == "" do
      acc
    else
      parts = String.split(line, delim)

      if length(parts) <= cols.date do
        acc
      else
        date = flex_date(Enum.at(parts, cols.date, ""))

        if date == "" do
          acc
        else
          amount = csv_amount(parts, cols)

          if amount in ["", "0.00"] do
            acc
          else
            tx = %{
              date: date,
              amount: amount,
              currency: currency,
              description: col(parts, cols.desc),
              contra_name: col(parts, cols.contra),
              contra_iban: "",
              reference: col(parts, cols.ref),
              is_duplicate: false
            }

            [tx | acc]
          end
        end
      end
    end
  end

  defp csv_amount(parts, cols) do
    cond do
      cols.debit && cols.credit ->
        debit = norm_money(col(parts, cols.debit))
        credit = norm_money(col(parts, cols.credit))

        cond do
          credit not in ["", "0.00"] -> credit
          debit not in ["", "0.00"] -> "-" <> String.trim_leading(debit, "-")
          true -> ""
        end

      cols.amount ->
        norm_money(col(parts, cols.amount))

      true ->
        ""
    end
  end

  defp col(_parts, nil), do: ""
  defp col(parts, index), do: parts |> Enum.at(index, "") |> String.trim()

  ## MT940

  defp parse_mt940(content) do
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
        amount = norm_money(amt)

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

  ## Общи помощници

  def norm_money(raw) do
    t = raw |> to_string() |> String.trim() |> String.replace(" ", "")

    if t == "" do
      ""
    else
      t =
        if String.contains?(t, ",") and String.contains?(t, "."),
          do: String.replace(t, ",", ""),
          else: String.replace(t, ",", ".")

      case Dec.parse(t) do
        nil -> ""
        value -> Dec.money(value)
      end
    end
  end

  def flex_date(raw) do
    t = String.trim(raw || "")

    cond do
      String.length(t) >= 10 and
          String.match?(String.slice(t, 0, 10), ~r/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) ->
        String.slice(t, 0, 10)

      true ->
        sep =
          cond do
            String.contains?(t, "/") -> "/"
            String.contains?(t, ".") -> "."
            String.contains?(t, "-") -> "-"
            true -> nil
          end

        if sep do
          parts = String.split(t, sep)

          if length(parts) == 3 do
            {y, m, d} =
              cond do
                String.length(Enum.at(parts, 0)) == 4 ->
                  {Enum.at(parts, 0), Enum.at(parts, 1), Enum.at(parts, 2)}

                String.length(Enum.at(parts, 2)) == 4 ->
                  {Enum.at(parts, 2), Enum.at(parts, 1), Enum.at(parts, 0)}

                true ->
                  {nil, nil, nil}
              end

            if y && String.length(y) == 4 do
              day = d |> String.trim() |> String.slice(0, 2)

              "#{y}-#{m |> String.trim() |> String.pad_leading(2, "0")}-#{day |> String.pad_leading(2, "0")}"
            else
              ""
            end
          else
            ""
          end
        else
          ""
        end
    end
  end
end

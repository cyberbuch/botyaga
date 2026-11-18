defmodule Botyaga.Banking.Formats.Csv do
  @moduledoc "CSV банкови извлечения с разделител `;`, `,` или `|`."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv

  @impl true
  def key, do: "csv"

  @impl true
  def name, do: "CSV"

  @impl true
  def matches?(content) do
    lower = String.downcase(content)

    (String.contains?(content, ";") or String.contains?(content, ",") or
       String.contains?(content, "|")) and
      (String.contains?(lower, "iban") or String.contains?(lower, "дата") or
         String.contains?(lower, "date"))
  end

  @impl true
  def parse(content) do
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
        date = Csv.flex_date(Enum.at(parts, cols.date, ""))

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
        debit = Csv.norm_money(col(parts, cols.debit))
        credit = Csv.norm_money(col(parts, cols.credit))

        cond do
          credit not in ["", "0.00"] -> credit
          debit not in ["", "0.00"] -> "-" <> String.trim_leading(debit, "-")
          true -> ""
        end

      cols.amount ->
        Csv.norm_money(col(parts, cols.amount))

      true ->
        ""
    end
  end

  defp col(_parts, nil), do: ""
  defp col(parts, index), do: parts |> Enum.at(index, "") |> String.trim()
end

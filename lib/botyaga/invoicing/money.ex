defmodule Botyaga.Invoicing.Money do
  @moduledoc """
  Суми като низ и знак на кредитно известие. Черното сторно е минус върху
  същите Дт/Кт — страните не се разменят. Фактурата брои в стотинки.
  """

  @credit ~w(03 13 23)
  @requires_original ~w(02 03 12 13 23)
  @common ~w(01 02 03 07 09 11 12 13)
  @out_extra ~w(04 23 29 50 81 82 83 84 85 91 93 94 95)
  @in_extra ~w(05 23 91 92 93 94)

  def is_credit(t), do: t in @credit
  def is_proforma(t), do: t == "proforma"
  def requires_original(t), do: t in @requires_original

  def valid_for(_direction, t) when t == "proforma", do: true

  def valid_for(direction, t) do
    if direction == "out" do
      t in @common or t in @out_extra
    else
      t in @common or t in @in_extra
    end
  end

  def title("02"), do: "ДЕБИТНО ИЗВЕСТИЕ"
  def title("03"), do: "КРЕДИТНО ИЗВЕСТИЕ"
  def title(t) when t in ["04", "05"], do: "РЕГИСТЪР НА СТОКИ ПОД РЕЖИМ СКЛАДИРАНЕ ДО ПОИСКВАНЕ"
  def title("07"), do: "МИТНИЧЕСКА ДЕКЛАРАЦИЯ"
  def title("09"), do: "ПРОТОКОЛ"
  def title("11"), do: "ФАКТУРА - КАСОВА ОТЧЕТНОСТ"
  def title("12"), do: "ДЕБИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ"
  def title("13"), do: "КРЕДИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ"
  def title("23"), do: "КРЕДИТНО ИЗВЕСТИЕ ПО ЧЛ. 126Б, АЛ. 1 ОТ ЗДДС"
  def title("29"), do: "ПРОТОКОЛ ПО ЧЛ. 126Б, АЛ. 2 И 7 ОТ ЗДДС"
  def title("50"), do: "ПРОТОКОЛ ЗА ИЗИСКУЕМИЯ ДДС ЗА ГОРИВА С КОМПЕНСАЦИИ"
  def title(t) when t in ["81", "83", "84", "85"], do: "ОТЧЕТ ЗА ИЗВЪРШЕНИТЕ ПРОДАЖБИ"
  def title("82"), do: "ОТЧЕТ ЗА ПРОДАЖБИ ПРИ СПЕЦИАЛЕН РЕД НА ОБЛАГАНЕ"

  def title(t) when t in ["91", "92", "93", "94"],
    do: "ПРОТОКОЛ ЗА ДАНЪК ПО ГЛАВА ДВАНАДЕСЕТА ОТ ЗДДС"

  def title("95"), do: "ПРОТОКОЛ ЗА БЕЗВЪЗМЕЗДНО ПРЕДОСТАВЯНЕ НА ХРАНИТЕЛНИ СТОКИ"
  def title("proforma"), do: "ПРОФОРМА ФАКТУРА"
  def title(_), do: "ФАКТУРА"

  @doc "Стотинки. `nil` ако низът не е число; третият знак закръгля."
  def cents(raw) when is_binary(raw) do
    s = raw |> String.trim() |> String.replace(" ", "") |> String.replace(",", ".")

    if s == "" do
      0
    else
      neg = String.starts_with?(s, "-")
      s = Regex.replace(~r/^[+-]+/, s, "")

      if s == "" do
        nil
      else
        {whole, frac} =
          case String.split(s, ".", parts: 2) do
            [w, f] -> {w, f}
            [w] -> {w, ""}
          end

        if digits?(whole) and digits?(frac) and (whole != "" or frac != "") do
          whole_v = if whole == "", do: 0, else: String.to_integer(whole)
          bytes = String.graphemes(frac)

          frac_cents =
            case bytes do
              [] -> 0
              [first] -> String.to_integer(first) * 10
              [first, second | _] -> String.to_integer(first) * 10 + String.to_integer(second)
            end

          frac_cents =
            if length(bytes) > 2 and Enum.at(bytes, 2) >= "5",
              do: frac_cents + 1,
              else: frac_cents

          v = whole_v * 100 + frac_cents
          if neg, do: -v, else: v
        end
      end
    end
  end

  def cents(_), do: nil

  defp digits?(s), do: s == "" or String.match?(s, ~r/^[0-9]+$/)

  def money(cents) when is_integer(cents) do
    neg = cents < 0
    v = Kernel.abs(cents)
    s = "#{div(v, 100)}.#{rem(v, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
    if neg, do: "-#{s}", else: s
  end

  @doc "Кредитно и още плюс → един минус. Отрицателно или нула не се пипа."
  def amount_for_doc(doc_type, amount) do
    if is_credit(doc_type) do
      case cents(amount) do
        c when is_integer(c) and c > 0 -> money(-c)
        _ -> amount
      end
    else
      amount
    end
  end

  def sum_amounts(amounts) do
    amounts
    |> Enum.map(&(cents(&1) || 0))
    |> Enum.sum()
    |> money()
  end
end

defmodule Botyaga.Printing.Words do
  @moduledoc "Сума словом на български. Същите думи като екрана на фактурата. Порт на `print_words.rs`."

  @ones {"", "един", "два", "три", "четири", "пет", "шест", "седем", "осем", "девет"}
  @ones_f {"", "една", "две", "три", "четири", "пет", "шест", "седем", "осем", "девет"}
  @teens {"десет", "единадесет", "дванадесет", "тринадесет", "четиринадесет", "петнадесет",
          "шестнадесет", "седемнадесет", "осемнадесет", "деветнадесет"}
  @tens {"", "", "двадесет", "тридесет", "четиридесет", "петдесет", "шестдесет", "седемдесет",
         "осемдесет", "деветдесет"}
  @hundreds {"", "сто", "двеста", "триста", "четиристотин", "петстотин", "шестстотин",
             "седемстотин", "осемстотин", "деветстотин"}

  def words(amount, currency) do
    raw = amount |> String.trim() |> String.replace(",", ".")
    neg = String.starts_with?(raw, "-")
    raw = String.replace(raw, ~r/^[+-]+/, "")

    {whole_s, frac_s} =
      case String.split(raw, ".", parts: 2) do
        [w, f] -> {w, f}
        [w] -> {w, ""}
      end

    whole = whole_s |> to_int() |> max(0)
    cents = cents_of(frac_s)
    female = currency == "BGN"
    {cur, cent_name} = money_name(currency, whole)
    out = "#{integer_words(whole, female)} #{cur}"
    out = if cents > 0, do: out <> " и #{pad2(cents)} #{cent_name}", else: out
    if neg, do: "минус " <> out, else: out
  end

  defp to_int(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp money_name("BGN", whole), do: {if(whole == 1, do: "лев", else: "лева"), "стотинки"}
  defp money_name("EUR", _whole), do: {"евро", "евроцента"}
  defp money_name(currency, _whole), do: {currency, "стотинки"}

  defp cents_of(frac) do
    digits = String.graphemes(frac)
    digit(Enum.at(digits, 0)) * 10 + digit(Enum.at(digits, 1))
  end

  defp digit(nil), do: 0
  defp digit(c), do: if(c in ~w(0 1 2 3 4 5 6 7 8 9), do: String.to_integer(c), else: 0)

  defp integer_words(n, _female) when n <= 0, do: "нула"
  defp integer_words(n, female) when n < 1_000_000, do: below_million(n, female)
  defp integer_words(n, _female) when n >= 1_000_000_000, do: Integer.to_string(n)

  defp integer_words(n, female) do
    mil = Kernel.div(n, 1_000_000)
    rest = rem(n, 1_000_000)
    head = if mil == 1, do: "един милион", else: "#{hundreds(mil, false)} милиона"

    cond do
      rest == 0 -> head
      rest < 1000 -> "#{head} и #{below_million(rest, female)}"
      true -> "#{head} #{below_million(rest, female)}"
    end
  end

  defp below_million(n, _female) when n <= 0, do: ""
  defp below_million(n, female) when n < 1000, do: hundreds(n, female)

  defp below_million(n, female) do
    th = Kernel.div(n, 1000)
    rest = rem(n, 1000)

    head =
      cond do
        th == 1 -> "хиляда"
        th == 2 -> "две хиляди"
        true -> "#{hundreds(th, true)} хиляди"
      end

    cond do
      rest == 0 -> head
      rest < 100 -> "#{head} и #{hundreds(rest, female)}"
      true -> "#{head} #{hundreds(rest, female)}"
    end
  end

  defp hundreds(n, _female) when n <= 0, do: ""

  defp hundreds(n, female) do
    ones = if female, do: @ones_f, else: @ones

    cond do
      n < 10 ->
        elem(ones, n)

      n < 20 ->
        elem(@teens, n - 10)

      n < 100 ->
        ten = Kernel.div(n, 10)
        one = rem(n, 10)
        if one == 0, do: elem(@tens, ten), else: "#{elem(@tens, ten)} и #{elem(ones, one)}"

      true ->
        h = Kernel.div(n, 100)
        rest = rem(n, 100)
        h_word = elem(@hundreds, h)

        cond do
          rest == 0 ->
            h_word

          rest < 10 ->
            "#{h_word} и #{elem(ones, rest)}"

          rest < 20 ->
            "#{h_word} и #{elem(@teens, rest - 10)}"

          true ->
            ten = Kernel.div(rest, 10)
            one = rem(rest, 10)

            if one == 0,
              do: "#{h_word} и #{elem(@tens, ten)}",
              else: "#{h_word} #{elem(@tens, ten)} и #{elem(ones, one)}"
        end
    end
  end
end

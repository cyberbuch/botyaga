defmodule Botyaga.Dec do
  @moduledoc """
  Суми с 6 знака вътре (цяло число, мащаб 1 000 000) — същата аритметика като
  `dec.rs` на ytbuch, включително закръглянето на половината away from zero.
  Навън: пари с 2 знака, количество с 4.
  """

  @scale 1_000_000

  def scale, do: @scale

  def or0(raw), do: parse(raw) || 0

  @doc "Низ → мащабирано цяло число. `nil` при нечетим низ, 0 при празен."
  def parse(raw) when is_binary(raw) do
    s = raw |> String.trim() |> String.replace(" ", "") |> String.replace("\u00A0", "")

    if s == "" do
      0
    else
      neg = String.starts_with?(s, "-")
      s = Regex.replace(~r/^[+-]+/, s, "")

      if s == "" do
        nil
      else
        {whole, frac} = split_fraction(s)

        if digits?(whole) and digits?(frac) and (whole != "" or frac != "") do
          whole_v = if whole == "", do: 0, else: String.to_integer(whole)
          frac_v = fraction_value(frac)
          v = whole_v * @scale + frac_v
          if neg, do: -v, else: v
        end
      end
    end
  end

  def parse(_), do: nil

  defp split_fraction(s) do
    case String.split(s, ".", parts: 2) do
      [whole, frac] ->
        {whole, frac}

      [whole] ->
        case String.split(whole, ",", parts: 2) do
          [w, f] -> {w, f}
          [w] -> {w, ""}
        end
    end
  end

  defp digits?(s), do: (s != "" and String.match?(s, ~r/^[0-9]+$/)) or s == ""

  defp fraction_value(frac) do
    digits = String.graphemes(frac)

    value =
      digits
      |> Enum.take(6)
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digit, index}, acc ->
        acc + String.to_integer(digit) * Integer.pow(10, 5 - index)
      end)

    if length(digits) > 6 and Enum.at(digits, 6) >= "5", do: value + 1, else: value
  end

  def add(a, b), do: a + b
  def sub(a, b), do: a - b
  def abs(v), do: Kernel.abs(v)

  def mul(a, b) do
    p = a * b
    half = Kernel.div(@scale, 2)
    p = if p >= 0, do: p + half, else: p - half
    Kernel.div(p, @scale)
  end

  def div(_a, 0), do: nil

  def div(a, b) do
    num = a * @scale
    half = Kernel.div(Kernel.abs(b), 2)
    num = if num >= 0, do: num + half, else: num - half
    Kernel.div(num, b)
  end

  @doc "Мащабирано число → низ с `dp` знака."
  def text(v, dp) do
    r = round_to(v, dp)
    neg = r < 0
    u = Kernel.abs(r)
    ip = Kernel.div(u, @scale)
    frac = rem(u, @scale)
    frac_s = frac |> Integer.to_string() |> String.pad_leading(6, "0") |> String.slice(0, dp)
    s = "#{ip}.#{frac_s}"
    if neg, do: "-#{s}", else: s
  end

  def money(v), do: text(v, 2)
  def qty(v), do: text(v, 4)

  defp round_to(v, dp) do
    unit = Integer.pow(10, 6 - dp)
    half = Kernel.div(unit, 2)

    if v >= 0 do
      Kernel.div(v + half, unit) * unit
    else
      -Kernel.div(-v + half, unit) * unit
    end
  end
end

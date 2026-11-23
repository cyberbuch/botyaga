defmodule Transport.Dec do
  @moduledoc "Суми и количества като низове; смята с Decimal."

  def num(raw) do
    case raw |> to_string() |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end

  def money(value), do: value |> num() |> Decimal.round(2) |> Decimal.to_string(:normal)

  def qty(value), do: value |> num() |> Decimal.round(2) |> Decimal.to_string(:normal)

  def add(a, b), do: Decimal.add(num(a), num(b))

  def mul(a, b), do: Decimal.mult(num(a), num(b))

  def zero?(value), do: Decimal.equal?(num(value), Decimal.new(0))
end

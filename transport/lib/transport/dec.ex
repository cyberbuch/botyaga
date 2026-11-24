defmodule Transport.Dec do
  @moduledoc "Суми и количества като низове; смята с Decimal."

  @doc "`{:ok, Decimal}` за цяло число/десетично (запетаята е допустима), иначе `:error`."
  def parse(raw) do
    case raw |> to_string() |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  def num(raw) do
    case parse(raw) do
      {:ok, d} -> d
      :error -> Decimal.new(0)
    end
  end

  @doc "Каноничен десетичен низ (запетаята се приема, изходът е с точка)."
  def canon(value), do: value |> num() |> Decimal.to_string(:normal)

  def money(value), do: value |> num() |> Decimal.round(2) |> Decimal.to_string(:normal)

  def qty(value), do: value |> num() |> Decimal.round(2) |> Decimal.to_string(:normal)

  def add(a, b), do: Decimal.add(num(a), num(b))

  def mul(a, b), do: Decimal.mult(num(a), num(b))

  def zero?(value), do: Decimal.equal?(num(value), Decimal.new(0))
end

defmodule Transport.Params do
  @moduledoc "Помощници за параметри и промени."

  def str(params, key) do
    case Map.get(params, key) do
      nil -> ""
      value -> value |> to_string() |> String.trim()
    end
  end

  def int(params, key) do
    case Integer.parse(str(params, key)) do
      {n, _} -> n
      :error -> 0
    end
  end

  def flag(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      value -> if value in [1, "1", true, "true"], do: 1, else: 0
    end
  end

  def required(params, key) do
    case str(params, key) do
      "" -> {:error, {422, "#{key} е задължително"}}
      value -> {:ok, value}
    end
  end

  def ok({:ok, struct}), do: {:ok, struct}
  def ok({:error, cs}), do: {:error, {422, inspect(cs.errors)}}
end

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

  @doc "Настоящите стойности, презаписани само по подадените ключове (смисълът на PATCH)."
  def merge(current, params), do: Map.merge(current, Map.take(params, Map.keys(current)))

  @doc "Стойностите на записа като низови ключове — базата за `merge/2` при PATCH."
  def current(struct, fields),
    do: Map.new(fields, fn field -> {Atom.to_string(field), Map.fetch!(struct, field)} end)

  @doc "`:ok`, или 422 за първото поле, което не е число (празно е нула)."
  def numeric(map, keys) do
    Enum.find_value(keys, :ok, fn key ->
      raw = str(map, key)

      if raw == "" or match?({:ok, _}, Transport.Dec.parse(raw)),
        do: nil,
        else: {:error, {422, "„#{key}“ трябва да е число"}}
    end)
  end

  @doc "Записва нов запис или обновява съществуващ по състоянието му."
  def save(changeset) do
    case changeset.data.__meta__.state do
      :built -> Transport.Repo.insert(changeset)
      _ -> Transport.Repo.update(changeset)
    end
    |> ok()
  end

  def ok({:ok, struct}), do: {:ok, struct}

  def ok({:error, cs}),
    do:
      {:error,
       {422, "невалидни полета: " <> Enum.map_join(cs.errors, ", ", &Atom.to_string(elem(&1, 0)))}}
end

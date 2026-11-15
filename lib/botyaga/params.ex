defmodule Botyaga.Params do
  @moduledoc """
  Помощници за тяло на заявката: липсващо поле не се пипа, `null` на низ го
  изчиства, числа и булеви стойности приемат и низ.
  """

  @doc "Връща `{:present, низ}` или `:absent`. Число се превръща в низ."
  def str(params, key) when is_map(params) do
    case fetch(params, key) do
      {:ok, nil} -> {:present, ""}
      {:ok, v} when is_binary(v) -> {:present, v}
      {:ok, v} when is_number(v) -> {:present, to_string(v)}
      {:ok, _} -> {:error, "#{key} трябва да е низ"}
      :error -> :absent
    end
  end

  def flag(params, key) when is_map(params) do
    case fetch(params, key) do
      :error -> nil
      {:ok, v} -> to_flag(v, key)
    end
  end

  def integer(params, key) when is_map(params) do
    case fetch(params, key) do
      :error -> nil
      {:ok, nil} -> 0
      {:ok, v} -> to_integer(v, key)
    end
  end

  def types_csv(params) when is_map(params) do
    case fetch(params, "document_types") do
      :error -> nil
      {:ok, nil} -> ""
      {:ok, v} when is_binary(v) -> v
      {:ok, list} when is_list(list) -> join_types(list)
      {:ok, _} -> {:error, "document_types трябва да е низ или списък"}
    end
  end

  defp join_types(list) do
    list
    |> Enum.reject(&(&1 == nil))
    |> Enum.map(&(&1 |> to_string() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  @doc "Идентификатор от път или тяло: цяло число, 0 при невалидно."
  def id(value) when is_integer(value), do: value

  def id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> 0
    end
  end

  def id(_), do: 0

  @doc "Списък с id-та за групова операция: непразен, до 500, положителни числа."
  def bulk_ids(params) do
    case Map.get(params, "ids") do
      nil ->
        {:error, {400, "липсва ids"}}

      arr when is_list(arr) ->
        cond do
          arr == [] -> {:error, {400, "ids е празен"}}
          length(arr) > 500 -> {:error, {400, "ids е твърде дълъг (макс 500)"}}
          true -> parse_ids(arr, 0, [])
        end

      _ ->
        {:error, {400, "ids трябва да е масив"}}
    end
  end

  defp parse_ids([], _index, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_ids([value | rest], index, acc) do
    number =
      cond do
        is_integer(value) ->
          value

        is_binary(value) ->
          case Integer.parse(String.trim(value)) do
            {n, ""} -> n
            _ -> nil
          end

        true ->
          nil
      end

    if is_nil(number) or number <= 0 do
      {:error, {400, "ids[#{index}] не е число"}}
    else
      parse_ids(rest, index + 1, [number | acc])
    end
  end

  defp fetch(params, key) when is_binary(key) do
    case Map.fetch(params, key) do
      {:ok, v} ->
        {:ok, v}

      :error ->
        atom = String.to_existing_atom(key)
        Map.fetch(params, atom)
    end
  rescue
    ArgumentError -> :error
  end

  defp to_flag(v, _key) when is_boolean(v), do: if(v, do: 1, else: 0)
  defp to_flag(v, _key) when is_number(v), do: if(v != 0, do: 1, else: 0)

  defp to_flag(v, key) when is_binary(v) do
    case String.trim(v) do
      "1" -> 1
      "true" -> 1
      "" -> 0
      "0" -> 0
      "false" -> 0
      _ -> {:error, "#{key} е невалидно"}
    end
  end

  defp to_flag(_, key), do: {:error, "#{key} е невалидно"}

  defp to_integer(v, _key) when is_integer(v), do: v
  defp to_integer(v, _key) when is_float(v), do: trunc(v)

  defp to_integer(v, key) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> {:error, "#{key} е невалидно"}
    end
  end

  defp to_integer(_, key), do: {:error, "#{key} е невалидно"}
end

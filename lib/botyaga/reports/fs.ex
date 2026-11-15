defmodule Botyaga.Reports.FS do
  @moduledoc """
  Финансови отчети по формули. Празен низ е нула, освен сборът на група.
  Предходната година още е нула. Формулата е сбор от сметки (`304Д`, `50*ОД`),
  кореспонденции (`702Д/304К`) и препратки (`@pl.e.5a`). Порт на `reports_fs.rs`.
  """

  alias Botyaga.Reports.{Data, Nom}

  @stop ["+", "-", "−", " ", "\t"]

  def check(raw) do
    case parse(raw) do
      {:ok, toks} -> {:ok, length(toks)}
      {:error, _} = err -> err
    end
  end

  def parse(raw) do
    chars = raw |> String.trim() |> String.graphemes()
    tokens(chars, true, [])
  end

  defp tokens([], _first, acc), do: {:ok, Enum.reverse(acc)}

  defp tokens(chars, first, acc) do
    case skip(chars) do
      [] ->
        {:ok, Enum.reverse(acc)}

      rest ->
        with {:ok, neg, rest} <- take_sign(rest, first),
             {:ok, piece, rest} <- take_piece(skip(rest)) do
          tokens(rest, false, [{neg, piece} | acc])
        end
    end
  end

  defp take_sign(["+" | rest], _first), do: {:ok, false, rest}
  defp take_sign([c | rest], _first) when c in ["-", "−"], do: {:ok, true, rest}
  defp take_sign(chars, true), do: {:ok, false, chars}
  defp take_sign(_chars, false), do: {:error, "очакван знак + или −"}

  defp take_piece([]), do: {:error, "формулата свършва след знака"}

  defp take_piece(["@" | rest]) do
    {code, rest2} = read_until(rest, "")

    if code == "",
      do: {:error, "липсва код след @"},
      else: {:ok, {:at, code}, rest2}
  end

  defp take_piece(chars) do
    {acc, rest} = read_acc(chars, "")

    if acc == "" do
      {:error, "липсва сметка"}
    else
      case kind_at(rest) do
        nil ->
          {:error, "липсва Д/К/ОД/ОК/НД/НК след #{acc}"}

        {kind, rest2} ->
          rest2 = skip(rest2)

          case rest2 do
            ["/" | rest3] ->
              {acc2, rest4} = read_acc(skip(rest3), "")

              if acc2 == "" do
                {:error, "липсва кредитна сметка след /"}
              else
                case kind_at(rest4) do
                  nil -> {:error, "липсва Д или К след втората сметка"}
                  {_kind2, rest5} -> {:ok, {:corr, acc, acc2}, rest5}
                end
              end

            _ ->
              {:ok, {:acct, acc, kind}, rest2}
          end
      end
    end
  end

  defp skip([c | rest]) when c in [" ", "\t"], do: skip(rest)
  defp skip(chars), do: chars

  defp read_acc([c | rest], acc) when c in ~w(0 1 2 3 4 5 6 7 8 9 *),
    do: read_acc(rest, acc <> c)

  defp read_acc(chars, acc), do: {acc, chars}

  defp read_until([c | rest], acc) when c in @stop, do: {acc, [c | rest]}
  defp read_until([c | rest], acc), do: read_until(rest, acc <> c)
  defp read_until([], acc), do: {acc, []}

  defp kind_at(chars) do
    cond do
      prefix?(chars, ["О", "Д"]) -> {"TD", Enum.drop(chars, 2)}
      prefix?(chars, ["О", "К"]) -> {"TC", Enum.drop(chars, 2)}
      prefix?(chars, ["Н", "Д"]) -> {"OD", Enum.drop(chars, 2)}
      prefix?(chars, ["Н", "К"]) -> {"OC", Enum.drop(chars, 2)}
      prefix?(chars, ["Д"]) -> {"D", Enum.drop(chars, 1)}
      prefix?(chars, ["К"]) -> {"C", Enum.drop(chars, 1)}
      true -> nil
    end
  end

  defp prefix?(chars, prefix), do: Enum.take(chars, length(prefix)) == prefix

  ## Изчисление

  def build(kind, books, formulas) do
    statement = Data.fs_statement(kind) || ""
    cat = Nom.lines(statement)
    turn = Data.turns(books)
    maps = Data.by_number(books, turn)
    pairs = Data.correspondences(books)

    val = resolve(cat, formulas, books, maps, pairs, MapSet.new(), %{}, length(cat) + 4)

    rows =
      Enum.map(cat, fn line ->
        amt = Map.get(val, line.code, 0)

        %{
          code: line.code,
          parent: line.parent,
          kind: line.kind,
          side: line.side,
          name: line.name,
          current: Data.money(amt),
          prior: Data.money(0)
        }
      end)

    grid =
      [[Data.title(kind)], ["#{books.from} — #{books.to}"], ["Статия", "Текуща", "Предходна"]] ++
        Enum.map(cat, fn line ->
          amt = Map.get(val, line.code, 0)

          if line.kind == "header",
            do: [line.name, "", ""],
            else: [line.name, Data.money(amt), Data.money(0)]
        end)

    body =
      books
      |> Data.head(kind)
      |> Map.put(:statement, statement)
      |> Map.put(:rows, rows)

    %{body: body, slug: Data.slug(kind), grid: grid}
  end

  defp resolve(_cat, _formulas, _books, _maps, _pairs, _done, val, passes) when passes <= 0,
    do: val

  defp resolve(cat, formulas, books, maps, pairs, done, val, passes) do
    {val, done, progress} =
      Enum.reduce(cat, {val, done, false}, fn line, {val, done, progress} ->
        if MapSet.member?(done, line.code) do
          {val, done, progress}
        else
          case line_value(line, cat, formulas, books, maps, pairs, done, val) do
            :wait -> {val, done, progress}
            {:ok, v} -> {Map.put(val, line.code, v), MapSet.put(done, line.code), true}
          end
        end
      end)

    if progress,
      do: resolve(cat, formulas, books, maps, pairs, done, val, passes - 1),
      else: val
  end

  defp line_value(line, cat, formulas, books, maps, pairs, done, val) do
    formula = Map.get(formulas, line.code, "")

    if formula == "" do
      if line.kind == "total",
        do: child_sum(cat, line.parent, line.code, done, val),
        else: {:ok, 0}
    else
      case parse(formula) do
        {:error, _} ->
          {:ok, 0}

        {:ok, toks} ->
          waiting =
            Enum.any?(toks, fn
              {_neg, {:at, code}} -> not MapSet.member?(done, code)
              _ -> false
            end)

          if waiting, do: :wait, else: {:ok, eval(toks, books, maps, pairs, val)}
      end
    end
  end

  defp child_sum(cat, parent, self_code, done, val) do
    children =
      Enum.filter(cat, fn line ->
        line.parent == parent and line.code != self_code and line.kind in ["line", "total"]
      end)

    if Enum.all?(children, &MapSet.member?(done, &1.code)) do
      {:ok, Enum.reduce(children, 0, fn line, s -> s + Map.get(val, line.code, 0) end)}
    else
      :wait
    end
  end

  defp eval(toks, books, maps, pairs, val) do
    Enum.reduce(toks, 0, fn {neg, piece}, acc ->
      v =
        case piece do
          {:at, code} -> Map.get(val, code, 0)
          {:acct, pat, which} -> sum_accounts(pat, which, books, maps)
          {:corr, debit, credit} -> sum_corr(debit, credit, pairs)
        end

      if neg, do: acc - v, else: acc + v
    end)
  end

  defp amount_of(which, num, maps) do
    g = fn i -> maps |> Enum.at(i) |> Map.get(num, 0) end

    case which do
      "D" -> g.(0) + g.(2)
      "C" -> g.(1) + g.(3)
      "TD" -> g.(2)
      "TC" -> g.(3)
      "OD" -> g.(0)
      "OC" -> g.(1)
      _ -> 0
    end
  end

  defp sum_accounts(pat, which, books, maps) do
    books.accounts
    |> Enum.map(& &1.number)
    |> Enum.uniq()
    |> Enum.filter(&Data.acc_match(&1, pat))
    |> Enum.reduce(0, fn num, s -> s + amount_of(which, num, maps) end)
  end

  defp sum_corr(debit, credit, pairs) do
    Enum.reduce(pairs, 0, fn {{d, c}, amount}, s ->
      if Data.acc_match(d, debit) and Data.acc_match(c, credit), do: s + amount, else: s
    end)
  end
end

defmodule Botyaga.Rates do
  @moduledoc """
  Курсове на ЕЦБ за 1 EUR. Дневният фид и историята за 90 дни, as-of търсене и
  кръстосан курс. Порт на `rates.rs`. Импортирането тегли фида през `Req`.
  """

  import Ecto.Query

  alias Botyaga.{Params, Repo}
  alias Botyaga.Rates.Rate

  @daily "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
  @history "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml"

  @doc "Курс за валута към 1 EUR към дата (най-близкият по-ранен при липса)."
  def rate(code, date) do
    code = String.upcase(code)

    if code == "EUR" do
      {:ok, {"1", date}}
    else
      case Repo.one(
             from(r in Rate,
               where: r.code == ^code and r.date <= ^date,
               order_by: [desc: r.date],
               select: {r.rate, r.date},
               limit: 1
             )
           ) do
        nil -> {:error, :no_rate}
        {rate, rate_date} -> {:ok, {rate, rate_date}}
      end
    end
  end

  @doc "Кръстосан курс: единици `to` за 1 `from`, през EUR, към дата."
  def cross_rate(from, to, date) do
    with {:ok, {from_rate, from_date}} <- rate(from, date),
         {:ok, {to_rate, _to_date}} <- rate(to, date),
         {:ok, cross} <- cross_value(from_rate, to_rate) do
      {:ok, {cross, from_date}}
    end
  end

  def index(params) do
    date = params |> str("date") |> String.trim()

    date =
      if date == "" do
        Repo.one(from(r in Rate, order_by: [desc: r.date], select: r.date, limit: 1)) || ""
      else
        date
      end

    if date == "" do
      {:ok, %{date: "", base: "EUR", items: []}}
    else
      items =
        Repo.all(from(r in Rate, where: r.date == ^date, order_by: [asc: r.code]))
        |> Enum.map(&%{id: &1.id, currency_code: &1.code, rate: &1.rate, date: &1.date})

      {:ok, %{date: date, base: "EUR", items: items}}
    end
  end

  def rate_query(params) do
    currency = params |> str("currency") |> String.trim() |> String.upcase()
    date = str(params, "date")

    cond do
      currency == "" ->
        {:error, {400, "currency е задължителен"}}

      String.trim(date) == "" ->
        {:error, {400, "date е задължителен (YYYY-MM-DD)"}}

      true ->
        case rate(currency, String.trim(date)) do
          {:ok, {rate, day}} ->
            {:ok, %{currency_code: currency, date: day, rate: rate, base: "EUR"}}

          {:error, :no_rate} ->
            {:error, {404, "няма курс за тази валута"}}
        end
    end
  end

  def cross(params) do
    from = params |> str("from") |> String.trim() |> String.upcase()
    to = params |> str("to") |> String.trim() |> String.upcase()
    date = params |> str("date") |> String.trim()

    cond do
      from == "" or to == "" ->
        {:error, {400, "from и to са задължителни"}}

      date == "" ->
        {:error, {400, "date е задължителен (YYYY-MM-DD)"}}

      true ->
        with {:ok, {rf, _}} <- per_eur(from, date),
             {:ok, {rt, rate_date}} <- per_eur(to, date),
             {:ok, rate} <- cross_value(rf, rt) do
          {:ok,
           %{
             from: from,
             to: to,
             rate: rate,
             rate_date: rate_date,
             requested_date: date,
             base: "EUR"
           }}
        end
    end
  end

  defp per_eur(code, date) do
    case rate(code, date) do
      {:ok, result} -> {:ok, result}
      {:error, :no_rate} -> {:error, {404, "няма курс за #{code}"}}
    end
  end

  def cross_value(rf, rt) do
    with {f, ""} <- Float.parse(rf),
         {t, ""} <- Float.parse(rt) do
      if f == 0.0,
        do: {:error, {422, "курсът е 0"}},
        else: {:ok, :erlang.float_to_binary(t / f, decimals: 6)}
    else
      _ -> {:error, {422, "невалиден курс"}}
    end
  end

  def import(params) do
    mode = params |> str("mode") |> String.trim()
    mode = if mode == "", do: "daily", else: mode

    if mode not in ["daily", "history"] do
      {:error, {422, "mode трябва да е daily или history"}}
    else
      url = if mode == "history", do: @history, else: @daily

      with {:ok, xml} <- fetch(url),
           {:ok, parsed} <- cubes(xml) do
        {:ok, upsert(mode, parsed)}
      end
    end
  end

  defp fetch(url) do
    case Req.get(url, receive_timeout: 40_000, retry: false) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {502, "ЕЦБ фидът върна статус #{status} — опитайте пак"}}

      {:error, _} ->
        {:error, {502, "ЕЦБ фидът е недостъпен"}}
    end
  end

  defp upsert(mode, parsed) do
    known =
      Repo.all(from(r in Rate))
      |> Map.new(&{{&1.code, &1.date}, {&1.id, &1.rate}})

    {known, counts, first, last} =
      Enum.reduce(parsed, {known, %{inserted: 0, updated: 0, unchanged: 0}, "", ""}, fn
        {code, rate, date}, {known, counts, first, last} ->
          first = if first == "" or date < first, do: date, else: first
          last = if last == "" or date > last, do: date, else: last
          key = {code, date}

          case Map.fetch(known, key) do
            {:ok, {_id, old}} when old == rate ->
              {known, %{counts | unchanged: counts.unchanged + 1}, first, last}

            {:ok, {id, _old}} ->
              Repo.update_all(from(r in Rate, where: r.id == ^id), set: [rate: rate])

              {Map.put(known, key, {id, rate}), %{counts | updated: counts.updated + 1}, first,
               last}

            :error ->
              r = Repo.insert!(%Rate{code: code, rate: rate, date: date})

              {Map.put(known, key, {r.id, rate}), %{counts | inserted: counts.inserted + 1},
               first, last}
          end
      end)

    _ = known

    %{
      mode: mode,
      inserted: counts.inserted,
      updated: counts.updated,
      unchanged: counts.unchanged,
      from_date: first,
      to_date: last
    }
  end

  @doc "Парсва Cube таговете на ЕЦБ: {код, курс, дата}. Празен резултат при XML → грешка."
  def cubes(xml) do
    {out, _date} = scan_cubes(xml, "", [])

    if out == [] and String.contains?(xml, "<"),
      do: {:error, "невалиден XML от ЕЦБ"},
      else: {:ok, Enum.reverse(out)}
  end

  defp scan_cubes(rest, date, acc) do
    case :binary.match(rest, "<") do
      :nomatch ->
        {acc, date}

      {pos, _} ->
        rest = drop(rest, pos + 1)

        if String.starts_with?(rest, "/") or String.starts_with?(rest, "!") or
             String.starts_with?(rest, "?") do
          scan_cubes(rest, date, acc)
        else
          case :binary.match(rest, ">") do
            :nomatch ->
              {acc, date}

            {end_pos, _} ->
              tag = binary_part(rest, 0, end_pos)
              rest2 = drop(rest, end_pos + 1)

              case quoted(tag, "time") do
                nil ->
                  code = quoted(tag, "currency")
                  rate = quoted(tag, "rate")

                  if code && rate && date != "",
                    do: scan_cubes(rest2, date, [{code, rate, date} | acc]),
                    else: scan_cubes(rest2, date, acc)

                day ->
                  scan_cubes(rest2, day, acc)
              end
          end
        end
    end
  end

  defp quoted(tag, key) do
    Enum.find_value(["\"", "'"], fn q ->
      needle = "#{key}=#{q}"

      case :binary.match(tag, needle) do
        :nomatch ->
          nil

        {pos, _} ->
          rest = drop(tag, pos + byte_size(needle))

          case :binary.match(rest, q) do
            :nomatch -> nil
            {stop, _} -> binary_part(rest, 0, stop)
          end
      end
    end)
  end

  defp drop(bin, n), do: binary_part(bin, n, byte_size(bin) - n)

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

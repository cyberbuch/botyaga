defmodule Botyaga.Periods do
  @moduledoc "Счетоводни месеци. Липсващ ред е отворен период; затворен спира поста."

  import Ecto.Query

  alias Botyaga.{Params, Repo}
  alias Botyaga.Periods.Period

  def assert_open(company_id, date_or_month) do
    key = key_of(date_or_month)
    {year, month} = parts(key)

    if year < 1 or month not in 1..12 do
      :ok
    else
      closed? =
        Repo.exists?(
          from(p in Period,
            where:
              p.company_id == ^company_id and p.year == ^year and p.month == ^month and
                p.status == "closed"
          )
        )

      if closed?, do: {:error, {422, "периодът #{key} е затворен"}}, else: :ok
    end
  end

  def index(company_id, year_param) do
    year = year_of(year_param)
    year_list(company_id, year)
  end

  def close(company_id, params) do
    with {:ok, year} <- required_int(params, "year"),
         {:ok, month} <- required_int(params, "month"),
         :ok <- check_month(month) do
      notes = string(params, "notes")
      closed_at = string(params, "closed_at")
      upsert(company_id, year, month, "closed", closed_at, notes)
      {:ok, year_list(company_id, year)}
    end
  end

  def reopen(company_id, params) do
    with {:ok, year} <- required_int(params, "year"),
         {:ok, month} <- required_int(params, "month") do
      case Repo.get_by(Period, company_id: company_id, year: year, month: month) do
        nil ->
          :ok

        period ->
          Repo.update!(Ecto.Changeset.change(period, status: "open", closed_at: "", notes: ""))
      end

      {:ok, year_list(company_id, year)}
    end
  end

  defp upsert(company_id, year, month, status, closed_at, notes) do
    case Repo.get_by(Period, company_id: company_id, year: year, month: month) do
      nil ->
        Repo.insert!(%Period{
          company_id: company_id,
          year: year,
          month: month,
          status: status,
          closed_at: closed_at,
          notes: notes
        })

      period ->
        Repo.update!(
          Ecto.Changeset.change(period, status: status, closed_at: closed_at, notes: notes)
        )
    end
  end

  defp year_list(company_id, year) do
    rows =
      Repo.all(
        from(p in Period,
          where: p.company_id == ^company_id and p.year == ^year,
          order_by: [asc: p.id]
        )
      )

    items =
      for month <- 1..12 do
        row = Enum.find(rows, &(&1.month == month))

        item = %{
          year: year,
          month: month,
          status: (row && row.status not in [nil, ""] && row.status) || "open",
          closed_at: (row && row.closed_at) || "",
          notes: (row && row.notes) || ""
        }

        if row && row.id > 0, do: Map.put(item, :id, row.id), else: item
      end

    %{items: items, year: year}
  end

  defp key_of(date) when is_binary(date) do
    if String.length(date) >= 7, do: String.slice(date, 0, 7), else: date
  end

  defp key_of(_), do: ""

  defp parts(key) do
    year = key |> String.slice(0, 4) |> to_int()
    month = if String.length(key) >= 7, do: key |> String.slice(5, 2) |> to_int(), else: 0
    {year, month}
  end

  defp year_of(raw) do
    n = raw |> to_string() |> String.trim() |> to_int()
    if n < 2000, do: 2026, else: n
  end

  defp required_int(params, key) do
    case Params.integer(params, key) do
      nil -> {:error, {422, "#{key} е задължително"}}
      {:error, message} -> {:error, {422, message}}
      value -> {:ok, value}
    end
  end

  defp check_month(month) do
    if month in 1..12, do: :ok, else: {:error, {422, "month трябва да е 1–12"}}
  end

  defp string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end

  defp to_int(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

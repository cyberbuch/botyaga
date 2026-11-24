defmodule Transport.Trips do
  @moduledoc """
  Командировки: работник, дестинация, дни, дневни (с/без нощувка), квартирни, аванс, отчет.
  Дневните се смятат по ставката на дестинацията (Наредба 2026, EUR).
  """

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo, Destinations}
  alias Transport.Trips.Trip

  @fields ~w(number worker_name start_date end_date lodging transport_cost advance note)a

  def list(company_id),
    do:
      Repo.all(from(t in Trip, where: t.company_id == ^company_id, order_by: [desc: t.id]))
      |> Enum.map(&json/1)

  def get(company_id, id), do: Repo.get_by(Trip, id: id, company_id: company_id)

  def create(company_id, params),
    do: write(%Trip{company_id: company_id, status: "draft"}, params)

  def update(%Trip{} = t, params) do
    if t.status == "reported" do
      {:error, {422, "отчетена командировка не се редактира"}}
    else
      current =
        %{"destination_id" => t.destination_id, "overnight" => t.overnight}
        |> Map.merge(current(t, @fields))

      write(t, merge(current, params))
    end
  end

  # Отчетената командировка е подписан документ — не се трие.
  def delete(%Trip{} = t) do
    if t.status == "reported",
      do: {:error, {422, "отчетена командировка не се изтрива"}},
      else: Repo.delete(t) |> ok()
  end

  def report(%Trip{} = t) do
    t |> Ecto.Changeset.change(status: "reported") |> Repo.update() |> ok()
  end

  defp write(%Trip{} = t, params) do
    {start_date, end_date} = {str(params, "start_date"), str(params, "end_date")}

    with {:ok, worker} <- required(params, "worker_name"),
         {:ok, dest} <- destination(params),
         {:ok, days} <- days_between(start_date, end_date),
         :ok <- numeric(params, ["lodging", "transport_cost", "advance"]) do
      overnight = flag(params, "overnight", 1)

      rate =
        cond do
          dest && overnight == 1 -> dest.per_diem
          dest -> dest.per_diem_no_overnight
          true -> str(params, "per_diem_rate")
        end

      %{
        number: str(params, "number"),
        worker_name: worker,
        destination_id: (dest && dest.id) || 0,
        start_date: start_date,
        end_date: end_date,
        days: days,
        overnight: overnight,
        per_diem_rate: rate,
        per_diem_total: Dec.money(Decimal.mult(Dec.num(rate), Decimal.new(days))),
        lodging: Dec.canon(default(str(params, "lodging"), "0")),
        lodging_limit: (dest && dest.lodging_limit) || "0",
        transport_cost: Dec.canon(default(str(params, "transport_cost"), "0")),
        advance: Dec.canon(default(str(params, "advance"), "0")),
        status: t.status,
        note: str(params, "note")
      }
      |> then(&Ecto.Changeset.change(t, &1))
      |> save()
    end
  end

  defp destination(params) do
    case int(params, "destination_id") do
      0 ->
        {:ok, nil}

      id ->
        case Destinations.get(id) do
          nil -> {:error, {422, "дестинацията не е намерена"}}
          dest -> {:ok, dest}
        end
    end
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  defp days_between(start_date, end_date) do
    with {:ok, s} <- Date.from_iso8601(start_date),
         {:ok, e} <- Date.from_iso8601(end_date) do
      if Date.compare(e, s) == :lt,
        do: {:error, {422, "крайната дата е преди началната"}},
        else: {:ok, Date.diff(e, s) + 1}
    else
      _ -> {:error, {422, "датите трябва да са валидни (ГГГГ-ММ-ДД)"}}
    end
  end

  def json(%Trip{} = t) do
    dest = if t.destination_id > 0, do: Destinations.get(t.destination_id)

    %{
      id: t.id,
      number: t.number,
      worker_name: t.worker_name,
      destination_id: t.destination_id,
      country: (dest && dest.country) || "",
      city: (dest && dest.city) || "",
      kind: (dest && dest.kind) || "",
      start_date: t.start_date,
      end_date: t.end_date,
      days: t.days,
      overnight: t.overnight,
      per_diem_rate: t.per_diem_rate,
      per_diem_total: t.per_diem_total,
      lodging: t.lodging,
      lodging_limit: t.lodging_limit,
      transport_cost: t.transport_cost,
      advance: t.advance,
      status: t.status,
      note: t.note
    }
  end
end

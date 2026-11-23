defmodule Transport.Trips do
  @moduledoc """
  Командировки: работник, дестинация, дни, дневни (с/без нощувка), квартирни, аванс, отчет.
  Дневните се смятат по ставката на дестинацията (Наредба 2026, EUR).
  """

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo, Destinations}
  alias Transport.Trips.Trip

  def list(company_id),
    do:
      Repo.all(from(t in Trip, where: t.company_id == ^company_id, order_by: [desc: t.id]))
      |> Enum.map(&json/1)

  def get(company_id, id), do: Repo.get_by(Trip, id: id, company_id: company_id)

  def create(company_id, params) do
    with {:ok, worker} <- required(params, "worker_name") do
      %Trip{} |> Ecto.Changeset.change(attrs(company_id, params, worker)) |> Repo.insert() |> ok()
    end
  end

  def update(%Trip{} = t, params) do
    with {:ok, worker} <-
           required(
             %{"worker_name" => Map.get(params, "worker_name", t.worker_name)},
             "worker_name"
           ) do
      t |> Ecto.Changeset.change(attrs(t.company_id, params, worker)) |> Repo.update() |> ok()
    end
  end

  def report(%Trip{} = t) do
    t |> Ecto.Changeset.change(status: "reported") |> Repo.update() |> ok()
  end

  def delete(%Trip{} = t), do: Repo.delete(t)

  defp attrs(company_id, params, worker) do
    dest_id = int(params, "destination_id")
    dest = if dest_id > 0, do: Destinations.get(dest_id)
    start_date = str(params, "start_date")
    end_date = str(params, "end_date")
    overnight = flag(params, "overnight", 1)
    days = days_between(start_date, end_date)

    rate =
      cond do
        dest && overnight == 1 -> dest.per_diem
        dest -> dest.per_diem_no_overnight
        true -> str(params, "per_diem_rate") |> default("0")
      end

    %{
      company_id: company_id,
      number: str(params, "number"),
      worker_name: worker,
      destination_id: dest_id,
      start_date: start_date,
      end_date: end_date,
      days: days,
      overnight: overnight,
      per_diem_rate: rate,
      per_diem_total: Dec.money(Decimal.mult(Dec.num(rate), Decimal.new(days))),
      lodging: str(params, "lodging") |> default("0"),
      lodging_limit: (dest && dest.lodging_limit) || "0",
      transport_cost: str(params, "transport_cost") |> default("0"),
      advance: str(params, "advance") |> default("0"),
      status: str(params, "status") |> default("draft"),
      note: str(params, "note")
    }
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  defp days_between(start_date, end_date) do
    with {:ok, s} <- Date.from_iso8601(start_date),
         {:ok, e} <- Date.from_iso8601(end_date),
         true <- Date.compare(e, s) != :lt do
      Date.diff(e, s) + 1
    else
      _ -> 0
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

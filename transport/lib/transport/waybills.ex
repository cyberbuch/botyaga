defmodule Transport.Waybills do
  @moduledoc """
  Пътни листове: маршрути и зареждания, начален/краен километраж и гориво,
  нормативен разход и приключване.
  """

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo, Vehicles}
  alias Transport.Waybills.{Waybill, Row}

  def list(company_id) do
    Repo.all(from(w in Waybill, where: w.company_id == ^company_id, order_by: [desc: w.id]))
    |> Enum.map(&summary/1)
  end

  def get(company_id, id) do
    case fetch(company_id, id) do
      nil -> nil
      w -> detail(w)
    end
  end

  def fetch(company_id, id), do: Repo.get_by(Waybill, id: id, company_id: company_id)

  def create(company_id, params) do
    with {:ok, date} <- required(params, "date") do
      attrs = header(company_id, params, date)
      w = %Waybill{} |> Ecto.Changeset.change(attrs) |> Repo.insert!()
      replace_rows(w.id, Map.get(params, "rows") || [])
      {:ok, detail(w)}
    end
  end

  def update(%Waybill{} = w, params) do
    if w.status == "closed" do
      {:error, {422, "приключен пътен лист не се редактира"}}
    else
      date = str(params, "date") |> default(w.date)
      w |> Ecto.Changeset.change(header(w.company_id, params, date)) |> Repo.update!()
      if Map.has_key?(params, "rows"), do: replace_rows(w.id, Map.get(params, "rows") || [])
      {:ok, detail(Repo.get(Waybill, w.id))}
    end
  end

  def close(%Waybill{} = w, params) do
    if w.status == "closed" do
      {:error, {422, "пътният лист е вече приключен"}}
    else
      d = detail(w)
      end_odo = str(params, "end_odometer") |> default(Decimal.to_string(d.expected_end_odometer))
      end_fuel = str(params, "end_fuel") |> default(Dec.money(d.expected_end_fuel))

      w
      |> Ecto.Changeset.change(end_odometer: end_odo, end_fuel: end_fuel, status: "closed")
      |> Repo.update!()

      {:ok, detail(Repo.get(Waybill, w.id))}
    end
  end

  def delete(%Waybill{} = w), do: Repo.delete(w)

  defp header(company_id, params, date) do
    %{
      company_id: company_id,
      number: str(params, "number"),
      vehicle_id: int(params, "vehicle_id"),
      driver_id: int(params, "driver_id"),
      approver: str(params, "approver"),
      date: date,
      start_odometer: str(params, "start_odometer") |> default("0"),
      start_fuel: str(params, "start_fuel") |> default("0"),
      note: str(params, "note")
    }
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  defp replace_rows(waybill_id, rows) do
    Repo.delete_all(from(r in Row, where: r.waybill_id == ^waybill_id))

    Enum.each(rows, fn r ->
      kind = if str(r, "kind") == "refuel", do: "refuel", else: "route"

      %Row{}
      |> Ecto.Changeset.change(%{
        waybill_id: waybill_id,
        kind: kind,
        date: str(r, "date"),
        description: str(r, "description"),
        city_km: str(r, "city_km") |> default("0"),
        out_km: str(r, "out_km") |> default("0"),
        winter: flag(r, "winter", 0),
        fuel_liters: str(r, "fuel_liters") |> default("0"),
        fuel_cost: str(r, "fuel_cost") |> default("0")
      })
      |> Repo.insert!()
    end)
  end

  defp rows_of(waybill_id),
    do: Repo.all(from(r in Row, where: r.waybill_id == ^waybill_id, order_by: [asc: r.id]))

  defp summary(w) do
    d = detail(w)

    %{
      id: w.id,
      number: w.number,
      date: w.date,
      status: w.status,
      vehicle_id: w.vehicle_id,
      vehicle_name: d.vehicle_name,
      plate: d.plate,
      driver_id: w.driver_id,
      driver_name: d.driver_name,
      total_km: d.total_km,
      norm_consumption: d.norm_consumption
    }
  end

  defp detail(w) do
    rows = rows_of(w.id)
    vehicle = if w.vehicle_id > 0, do: Vehicles.get(w.company_id, w.vehicle_id)
    driver = if w.driver_id > 0, do: Transport.Drivers.get(w.company_id, w.driver_id)
    calc = compute(w, rows, vehicle)

    %{
      id: w.id,
      number: w.number,
      date: w.date,
      status: w.status,
      vehicle_id: w.vehicle_id,
      vehicle_name: (vehicle && vehicle.name) || "",
      plate: (vehicle && vehicle.plate) || "",
      fuel: (vehicle && vehicle.fuel) || "",
      norm: (vehicle && vehicle.norm) || "0",
      driver_id: w.driver_id,
      driver_name: (driver && driver.name) || "",
      approver: w.approver,
      start_odometer: w.start_odometer,
      start_fuel: w.start_fuel,
      end_odometer: w.end_odometer,
      end_fuel: w.end_fuel,
      note: w.note,
      rows: Enum.map(rows, &row_json/1),
      total_km: calc.total_km,
      total_refuel: calc.total_refuel,
      norm_consumption: calc.norm_consumption,
      expected_end_fuel: calc.expected_end_fuel,
      expected_end_odometer: calc.expected_end_odometer
    }
  end

  defp row_json(r) do
    %{
      id: r.id,
      kind: r.kind,
      date: r.date,
      description: r.description,
      city_km: r.city_km,
      out_km: r.out_km,
      winter: r.winter,
      fuel_liters: r.fuel_liters,
      fuel_cost: r.fuel_cost
    }
  end

  defp compute(w, rows, vehicle) do
    norm = Dec.num(vehicle && vehicle.norm)
    surcharge = Decimal.new((vehicle && vehicle.winter_surcharge) || 0)
    factor = Decimal.add(Decimal.new(1), Decimal.div(surcharge, Decimal.new(100)))

    routes = Enum.filter(rows, &(&1.kind == "route"))

    total_km =
      Enum.reduce(routes, Decimal.new(0), fn r, acc ->
        Decimal.add(acc, Decimal.add(Dec.num(r.city_km), Dec.num(r.out_km)))
      end)

    effective_km =
      Enum.reduce(routes, Decimal.new(0), fn r, acc ->
        km = Decimal.add(Dec.num(r.city_km), Dec.num(r.out_km))
        km = if r.winter == 1, do: Decimal.mult(km, factor), else: km
        Decimal.add(acc, km)
      end)

    total_refuel =
      Enum.reduce(rows, Decimal.new(0), fn r, acc ->
        if r.kind == "refuel", do: Decimal.add(acc, Dec.num(r.fuel_liters)), else: acc
      end)

    consumption =
      effective_km
      |> Decimal.mult(Decimal.div(norm, Decimal.new(100)))
      |> Decimal.round(2, :half_even)

    expected_fuel =
      Dec.num(w.start_fuel)
      |> Decimal.add(total_refuel)
      |> Decimal.sub(consumption)
      |> Decimal.round(2)

    expected_odo = Dec.num(w.start_odometer) |> Decimal.add(total_km) |> Decimal.round(1)

    %{
      total_km: Dec.qty(total_km),
      total_refuel: Dec.money(total_refuel),
      norm_consumption: Dec.money(consumption),
      expected_end_fuel: expected_fuel,
      expected_end_odometer: expected_odo
    }
  end
end

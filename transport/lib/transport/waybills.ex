defmodule Transport.Waybills do
  @moduledoc """
  Пътни листове: маршрути и зареждания, начален/краен километраж и гориво,
  нормативен разход и приключване. Приключеният лист пази норматива и изчисленията
  към момента — по-късна промяна на автомобила не го пренаписва.
  """

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo, Vehicles}
  alias Transport.Vehicles.Vehicle
  alias Transport.Waybills.{Waybill, Row}

  @fields ~w(number vehicle_id driver_id approver date start_odometer start_fuel note)a
  @numeric ~w(start_odometer start_fuel)a
  @row_numeric ~w(city_km out_km fuel_liters fuel_cost)a

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

  def create(company_id, params), do: write(%Waybill{company_id: company_id}, params)

  def update(%Waybill{} = w, params) do
    if w.status == "closed" do
      {:error, {422, "приключен пътен лист не се редактира"}}
    else
      write(w, merge(current(w, @fields), params))
    end
  end

  # Приключеният пътен лист е подписан документ — не се трие.
  def delete(%Waybill{} = w) do
    if w.status == "closed",
      do: {:error, {422, "приключен пътен лист не се изтрива"}},
      else: Repo.delete(w) |> ok()
  end

  def close(%Waybill{} = w, params) do
    if w.status == "closed" do
      {:error, {422, "пътният лист е вече приключен"}}
    else
      calc = compute(w, rows_of(w.id), vehicle_of(w))

      end_odo =
        default(str(params, "end_odometer"), Decimal.to_string(calc.expected_end_odometer))

      end_fuel = default(str(params, "end_fuel"), Decimal.to_string(calc.expected_end_fuel))

      with {:ok, odo} <- number(end_odo, "end_odometer"),
           {:ok, fuel} <- number(end_fuel, "end_fuel"),
           :ok <- at_least_start(odo, Dec.num(w.start_odometer)),
           :ok <- non_negative(fuel) do
        w
        |> Ecto.Changeset.change(%{
          end_odometer: Decimal.to_string(odo),
          end_fuel: Dec.money(fuel),
          status: "closed",
          norm: calc.norm,
          winter_surcharge: calc.winter_surcharge,
          total_km: calc.total_km,
          total_refuel: calc.total_refuel,
          norm_consumption: calc.norm_consumption
        })
        |> Repo.update()
        |> case do
          {:ok, closed} -> {:ok, detail(closed)}
          {:error, _cs} -> {:error, {422, "пътният лист не се записа"}}
        end
      end
    end
  end

  defp number(raw, key) do
    case Dec.parse(raw) do
      {:ok, d} -> {:ok, d}
      :error -> {:error, {422, "„#{key}“ трябва да е число"}}
    end
  end

  defp at_least_start(odo, start) do
    if Decimal.compare(odo, start) in [:gt, :eq],
      do: :ok,
      else: {:error, {422, "крайният километраж е преди началния"}}
  end

  defp non_negative(fuel) do
    if Decimal.negative?(fuel),
      do: {:error, {422, "крайното гориво не може да е отрицателно"}},
      else: :ok
  end

  defp write(%Waybill{} = w, params) do
    with {:ok, date} <- required(params, "date"),
         :ok <- iso_date(date),
         :ok <- numeric(params, @numeric),
         :ok <- owner(w.company_id, params, "vehicle_id", "автомобилът"),
         :ok <- owner(w.company_id, params, "driver_id", "шофьорът"),
         {:ok, rows} <- cast_rows(params) do
      Repo.transaction(fn ->
        w =
          %{
            number: str(params, "number"),
            vehicle_id: int(params, "vehicle_id"),
            driver_id: int(params, "driver_id"),
            approver: str(params, "approver"),
            date: date,
            start_odometer: Dec.canon(default(str(params, "start_odometer"), "0")),
            start_fuel: Dec.canon(default(str(params, "start_fuel"), "0")),
            note: str(params, "note")
          }
          |> then(&Ecto.Changeset.change(w, &1))
          |> Repo.insert_or_update!()

        if Map.has_key?(params, "rows") do
          Repo.delete_all(from(r in Row, where: r.waybill_id == ^w.id))

          Enum.each(rows, fn attrs ->
            %Row{} |> Ecto.Changeset.change(Map.put(attrs, :waybill_id, w.id)) |> Repo.insert!()
          end)
        end

        w
      end)
      |> case do
        {:ok, w} -> {:ok, detail(Repo.get!(Waybill, w.id))}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp iso_date(date) do
    case Date.from_iso8601(date) do
      {:ok, _} -> :ok
      _ -> {:error, {422, "датата трябва да е валидна (ГГГГ-ММ-ДД)"}}
    end
  end

  defp owner(company_id, params, key, what) do
    id = int(params, key)
    schema = if key == "vehicle_id", do: Vehicle, else: Transport.Drivers.Driver

    exists =
      Repo.exists?(where(schema, [x], x.id == ^id and x.company_id == ^company_id))

    if id == 0 or exists,
      do: :ok,
      else: {:error, {422, "#{what} не е от тази фирма"}}
  end

  # Редовете са списък от обекти; километрите и литрите — числа. Липсващ ключ не пипа редовете.
  defp cast_rows(params) do
    case Map.get(params, "rows") do
      nil -> {:ok, []}
      rows when is_list(rows) -> cast_row_list(rows)
      _ -> {:error, {422, "редовете трябва да са списък"}}
    end
  end

  defp cast_row_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      if is_map(row) do
        case numeric(row, @row_numeric) do
          :ok ->
            {:cont, {:ok, [row_attrs(row) | acc]}}

          error ->
            {:halt, error}
        end
      else
        {:halt, {:error, {422, "всеки ред трябва да е обект"}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp row_attrs(r) do
    %{
      kind: if(str(r, "kind") == "refuel", do: "refuel", else: "route"),
      date: str(r, "date"),
      description: str(r, "description"),
      city_km: Dec.canon(default(str(r, "city_km"), "0")),
      out_km: Dec.canon(default(str(r, "out_km"), "0")),
      winter: flag(r, "winter", 0),
      fuel_liters: Dec.canon(default(str(r, "fuel_liters"), "0")),
      fuel_cost: Dec.canon(default(str(r, "fuel_cost"), "0"))
    }
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  defp rows_of(waybill_id),
    do: Repo.all(from(r in Row, where: r.waybill_id == ^waybill_id, order_by: [asc: r.id]))

  defp vehicle_of(w), do: if(w.vehicle_id > 0, do: Vehicles.get(w.company_id, w.vehicle_id))

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
    vehicle = vehicle_of(w)
    driver = if(w.driver_id > 0, do: Transport.Drivers.get(w.company_id, w.driver_id))
    calc = figures(w, rows, vehicle)

    %{
      id: w.id,
      number: w.number,
      date: w.date,
      status: w.status,
      vehicle_id: w.vehicle_id,
      vehicle_name: (vehicle && vehicle.name) || "",
      plate: (vehicle && vehicle.plate) || "",
      fuel: (vehicle && vehicle.fuel) || "",
      norm: calc.norm,
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

  # Приключен лист със замразени стойности: не се смята втори път.
  defp figures(%Waybill{status: "closed", norm_consumption: frozen} = w, _rows, _vehicle)
       when frozen != "" do
    %{
      norm: w.norm,
      winter_surcharge: w.winter_surcharge,
      total_km: w.total_km,
      total_refuel: w.total_refuel,
      norm_consumption: w.norm_consumption,
      expected_end_fuel:
        Dec.num(w.start_fuel)
        |> Decimal.add(Dec.num(w.total_refuel))
        |> Decimal.sub(Dec.num(w.norm_consumption))
        |> Decimal.round(2, :half_even),
      expected_end_odometer: Dec.num(w.start_odometer) |> Decimal.add(Dec.num(w.total_km))
    }
  end

  defp figures(w, rows, vehicle), do: compute(w, rows, vehicle)

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
      |> Decimal.round(2, :half_even)

    expected_odo = Dec.num(w.start_odometer) |> Decimal.add(total_km) |> Decimal.round(1)

    %{
      norm: (vehicle && vehicle.norm) || "0",
      winter_surcharge: (vehicle && vehicle.winter_surcharge) || 0,
      total_km: Dec.qty(total_km),
      total_refuel: Dec.money(total_refuel),
      norm_consumption: Dec.money(consumption),
      expected_end_fuel: expected_fuel,
      expected_end_odometer: expected_odo
    }
  end
end

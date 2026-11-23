defmodule TransportWeb.ApiTest do
  use TransportWeb.ConnCase, async: false

  defp ac(conn), do: auth_conn(recycle(conn))

  test "без токен → 401", %{conn: conn} do
    conn = get(conn, "/v1/vehicles")
    assert json_response(conn, 401)
  end

  test "автомобили CRUD", %{conn: conn} do
    conn =
      ac(conn)
      |> post("/v1/vehicles", %{
        "name" => "Служебен автомобил",
        "plate" => "CA1234AB",
        "fuel" => "Дизел",
        "norm" => "7.5",
        "winter_surcharge" => 10
      })

    v = json_response(conn, 201)
    assert v["plate"] == "CA1234AB"

    conn = ac(conn) |> get("/v1/vehicles")
    assert length(json_response(conn, 200)["items"]) == 1

    conn = ac(conn) |> patch("/v1/vehicles/#{v["id"]}", %{"norm" => "8"})
    assert json_response(conn, 200)["norm"] == "8"
  end

  test "пътен лист смята норматив и приключване", %{conn: conn} do
    v =
      json_response(
        ac(conn)
        |> post("/v1/vehicles", %{"name" => "Кола", "norm" => "7.5", "winter_surcharge" => 0}),
        201
      )

    d = json_response(ac(conn) |> post("/v1/drivers", %{"name" => "Иван Петров"}), 201)

    conn =
      ac(conn)
      |> post("/v1/waybills", %{
        "date" => "2026-11-01",
        "vehicle_id" => v["id"],
        "driver_id" => d["id"],
        "approver" => "Георги Георгиев",
        "start_odometer" => "12500",
        "start_fuel" => "35",
        "rows" => [
          %{
            "kind" => "route",
            "description" => "София-Пловдив",
            "city_km" => "15",
            "out_km" => "280"
          },
          %{"kind" => "refuel", "fuel_liters" => "25", "fuel_cost" => "62.50"}
        ]
      })

    w = json_response(conn, 201)
    assert w["total_km"] == "295.00"
    assert w["norm_consumption"] == "22.12"
    assert w["expected_end_fuel"] == "37.88"
    assert w["status"] == "open"

    conn = ac(conn) |> post("/v1/waybills/#{w["id"]}/close", %{})
    closed = json_response(conn, 200)
    assert closed["status"] == "closed"
    assert closed["end_fuel"] == "37.88"
    assert closed["end_odometer"] == "12795.0"
  end

  test "командировка смята дневни по дестинация", %{conn: conn} do
    dest =
      json_response(
        ac(conn)
        |> post("/v1/destinations", %{
          "country" => "Германия",
          "kind" => "abroad",
          "per_diem" => "56",
          "lodging_limit" => "207"
        }),
        201
      )

    conn =
      ac(conn)
      |> post("/v1/trips", %{
        "worker_name" => "Петър Работник",
        "destination_id" => dest["id"],
        "start_date" => "2026-11-01",
        "end_date" => "2026-11-03",
        "overnight" => 1,
        "lodging" => "180"
      })

    t = json_response(conn, 201)
    assert t["days"] == 3
    assert t["per_diem_rate"] == "56"
    assert t["per_diem_total"] == "168.00"
    assert t["lodging_limit"] == "207"

    conn = ac(conn) |> post("/v1/trips/#{t["id"]}/report", %{})
    assert json_response(conn, 200)["status"] == "reported"
  end
end

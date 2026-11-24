defmodule TransportWeb.ApiTest do
  use TransportWeb.ConnCase, async: false

  defp ac(conn), do: auth_conn(recycle(conn))

  defp bearer(sub),
    do:
      get_req_header(auth_conn(recycle(Phoenix.ConnTest.build_conn()), sub, 1), "authorization")
      |> hd()
      |> String.trim_leading("Bearer ")

  test "връзката към botyaga е пусната като дете на надзорника" do
    assert Process.whereis(Transport.Botyaga)
  end

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
        "norm" => "7,5",
        "winter_surcharge" => 10
      })

    v = json_response(conn, 201)
    assert v["plate"] == "CA1234AB"

    # Десетичната запетая се приема и се записва канонично с точка.
    assert v["norm"] == "7.5"

    conn = ac(conn) |> get("/v1/vehicles")
    assert length(json_response(conn, 200)["items"]) == 1

    conn = ac(conn) |> patch("/v1/vehicles/#{v["id"]}", %{"norm" => "8"})
    patched = json_response(conn, 200)
    assert patched["norm"] == "8"
    # PATCH пази всичко, което не е подадено.
    assert patched["plate"] == "CA1234AB"
    assert patched["winter_surcharge"] == 10
    assert patched["active"] == 1
  end

  test "фирмата от заглавката се проверява срещу членството", %{conn: conn} do
    ac(conn) |> post("/v1/vehicles", %{"name" => "Кола на фирма 1"})
    sub = "test@baga.example"

    # Чужда фирма: четене и писане са отказани.
    conn = auth_conn(recycle(conn), sub, 2) |> get("/v1/vehicles")
    assert json_response(conn, 403)

    conn = auth_conn(recycle(conn), sub, 2) |> post("/v1/vehicles", %{"name" => "Чужда"})
    assert json_response(conn, 403)

    # Липсваща или неравноцинна фирма.
    conn =
      auth_conn(recycle(conn), sub, 1) |> delete_req_header("x-company-id") |> get("/v1/vehicles")

    assert json_response(conn, 403)

    conn =
      auth_conn(recycle(conn), sub, 1)
      |> put_req_header("x-company-id", "1 or 2")
      |> get("/v1/vehicles")

    assert json_response(conn, 403)

    # Неизвестен потребител.
    conn = auth_conn(recycle(conn), "ghost@baga.example", 1) |> get("/v1/vehicles")
    assert json_response(conn, 401)

    # С добавено членство фирмата се вижда — и е празна, не със записите на фирма 1.
    grant_company(sub, 2)
    conn = auth_conn(recycle(conn), sub, 2) |> get("/v1/vehicles")
    assert json_response(conn, 200)["items"] == []
  end

  test "фалшив подпис и чужд издател не минават", %{conn: conn} do
    token = bearer("test@baga.example")
    [h, p, _sig] = String.split(token, ".")

    forged = "#{h}.#{p}.#{String.duplicate("A", 43)}"
    conn = conn |> put_req_header("authorization", "Bearer #{forged}") |> get("/v1/vehicles")
    assert json_response(conn, 401)

    {:ok, claims} = p |> Base.url_decode64!(padding: false) |> Jason.decode()

    other =
      claims |> Map.put("iss", "other") |> Jason.encode!() |> Base.url_encode64(padding: false)

    {:ok, secret} = Transport.Auth.secret()

    mac =
      :crypto.mac(:hmac, :sha256, secret, "#{h}.#{other}") |> Base.url_encode64(padding: false)

    conn =
      recycle(conn)
      |> put_req_header("authorization", "Bearer #{h}.#{other}.#{mac}")
      |> get("/v1/vehicles")

    assert json_response(conn, 401)
  end

  test "числови полета се отказват, а не се зануляват", %{conn: conn} do
    conn = ac(conn) |> post("/v1/vehicles", %{"name" => "Кола", "norm" => "седем"})
    assert json_response(conn, 422)
  end

  test "автомобил с пътни листове не се изтрива", %{conn: conn} do
    v = json_response(ac(conn) |> post("/v1/vehicles", %{"name" => "Кола"}), 201)

    w =
      json_response(
        ac(conn) |> post("/v1/waybills", %{"date" => "2026-11-01", "vehicle_id" => v["id"]}),
        201
      )

    assert w["norm_consumption"] == "0.00"

    conn = ac(conn) |> delete("/v1/vehicles/#{v["id"]}")
    assert json_response(conn, 422)
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

    # Приключване с невъзможни стойности се отказва.
    conn = ac(conn) |> post("/v1/waybills/#{w["id"]}/close", %{"end_odometer" => "12400"})
    assert json_response(conn, 422)
    conn = ac(conn) |> post("/v1/waybills/#{w["id"]}/close", %{"end_fuel" => "-1"})
    assert json_response(conn, 422)
    conn = ac(conn) |> post("/v1/waybills/#{w["id"]}/close", %{"end_fuel" => "празно"})
    assert json_response(conn, 422)

    conn = ac(conn) |> post("/v1/waybills/#{w["id"]}/close", %{})
    closed = json_response(conn, 200)
    assert closed["status"] == "closed"
    assert closed["end_fuel"] == "37.88"
    assert closed["end_odometer"] == "12795.0"

    # Приключеният лист не се редактира и не се трие.
    conn = ac(conn) |> patch("/v1/waybills/#{w["id"]}", %{"note" => "наче"})
    assert json_response(conn, 422)
    conn = ac(conn) |> delete("/v1/waybills/#{w["id"]}")
    assert json_response(conn, 422)

    # Изчисленията са замразени: нов норматив на автомобила не го променя.
    ac(conn) |> patch("/v1/vehicles/#{v["id"]}", %{"norm" => "12"})
    conn = ac(conn) |> get("/v1/waybills/#{w["id"]}")
    frozen = json_response(conn, 200)
    assert frozen["norm_consumption"] == "22.12"
    assert frozen["norm"] == "7.5"

    # Отворен лист пази пропуснатите полета при PATCH.
    open =
      json_response(
        ac(conn)
        |> post("/v1/waybills", %{
          "date" => "2026-11-02",
          "number" => "17",
          "start_odometer" => "100"
        }),
        201
      )

    conn = ac(conn) |> patch("/v1/waybills/#{open["id"]}", %{"approver" => "Мария"})
    patched = json_response(conn, 200)
    assert patched["number"] == "17"
    assert patched["start_odometer"] == "100"
    assert patched["approver"] == "Мария"

    # Лош ред не оставя половин лист.
    conn =
      ac(conn)
      |> post("/v1/waybills", %{"date" => "2026-11-03", "number" => "18", "rows" => ["лош"]})

    assert json_response(conn, 422)
    conn = ac(conn) |> get("/v1/waybills")
    refute Enum.any?(json_response(conn, 200)["items"], &(&1["number"] == "18"))
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

    # Отчетена командировка не се редактира; PATCH не я връща в чернова.
    conn = ac(conn) |> patch("/v1/trips/#{t["id"]}", %{"lodging" => "190"})
    assert json_response(conn, 200)["status"] == "draft"

    conn = ac(conn) |> post("/v1/trips/#{t["id"]}/report", %{})
    assert json_response(conn, 200)["status"] == "reported"

    conn = ac(conn) |> patch("/v1/trips/#{t["id"]}", %{"lodging" => "200"})
    assert json_response(conn, 422)
    conn = ac(conn) |> delete("/v1/trips/#{t["id"]}")
    assert json_response(conn, 422)

    # Обратни, липсващи дати и несъществуваща дестинация се отказват, а не дават 0 дни.
    base = %{"worker_name" => "Петър Работник", "destination_id" => dest["id"]}

    for bad <- [
          %{"start_date" => "2026-11-05", "end_date" => "2026-11-03"},
          %{"start_date" => "", "end_date" => ""}
        ] do
      conn = ac(conn) |> post("/v1/trips", Map.merge(base, bad))
      assert json_response(conn, 422)
    end

    conn = ac(conn) |> post("/v1/trips", Map.put(base, "destination_id", 999_999))
    assert json_response(conn, 422)

    # Дестинация с командировка не се изтрива.
    conn = ac(conn) |> delete("/v1/destinations/#{dest["id"]}")
    assert json_response(conn, 422)
  end
end

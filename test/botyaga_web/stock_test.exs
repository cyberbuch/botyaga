defmodule BotyagaWeb.StockTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("stock@baga.example", "Склад", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Склад ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
        201
      )

    customer =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "222333444"}),
        201
      )

    goods =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["302"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    {:ok,
     conn: conn, company: company, by_number: by_number, cp: cp, customer: customer, goods: goods}
  end

  defp purchase(conn, cp, goods, qty, price, date, number) do
    net = :erlang.float_to_binary(qty * price, decimals: 2)
    vat = :erlang.float_to_binary(qty * price * 0.2, decimals: 2)
    total = :erlang.float_to_binary(qty * price * 1.2, decimals: 2)

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => number,
          "issue_date" => date,
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => goods["id"],
              "description" => "Покупка",
              "quantity" => "#{qty}",
              "unit_price" => :erlang.float_to_binary(price, decimals: 2),
              "vat_rate" => "20",
              "net_amount" => net,
              "vat_amount" => vat,
              "total_amount" => total
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    inv
  end

  defp sale(conn, customer, goods, qty, date) do
    net = :erlang.float_to_binary(qty * 300.0, decimals: 2)
    vat = :erlang.float_to_binary(qty * 300.0 * 0.2, decimals: 2)
    total = :erlang.float_to_binary(qty * 300.0 * 1.2, decimals: 2)

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "issue_date" => date,
          "counterpart_id" => customer["id"],
          "lines" => [
            %{
              "product_id" => goods["id"],
              "description" => "Продажба",
              "quantity" => "#{qty}",
              "unit_price" => "300.00",
              "vat_rate" => "20",
              "net_amount" => net,
              "vat_amount" => vat,
              "total_amount" => total
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    inv
  end

  defp product(conn, goods) do
    json_response(get(conn, "/v1/products/#{goods["id"]}"), 200)
  end

  test "WAC: среднопретеглена себестойност", %{
    conn: conn,
    cp: cp,
    customer: customer,
    goods: goods
  } do
    purchase(conn, cp, goods, 10, 100.0, "2026-01-01", "P-1")
    purchase(conn, cp, goods, 10, 200.0, "2026-01-02", "P-2")

    p = product(conn, goods)
    assert p["stock_quantity"] == "20.0000"
    assert p["stock_value"] == "3000.00"
    assert p["cost_price"] == "150.000000"

    sale(conn, customer, goods, 5, "2026-01-03")
    p = product(conn, goods)
    assert p["stock_quantity"] == "15.0000"
    assert p["stock_value"] == "2250.00"
  end

  test "FIFO и LIFO по партиди", %{
    conn: conn,
    company: company,
    cp: cp,
    customer: customer,
    goods: goods
  } do
    purchase(conn, cp, goods, 10, 100.0, "2026-01-01", "P-1")
    purchase(conn, cp, goods, 10, 200.0, "2026-01-02", "P-2")

    patch(conn, "/v1/companies/#{company.id}", %{"inventory_valuation_method" => "FIFO"})
    sale(conn, customer, goods, 5, "2026-01-03")
    p = product(conn, goods)

    # FIFO: продадени 5 от първата партида (100) → остават 5@100 + 10@200 = 2500
    assert p["stock_value"] == "2500.00"

    patch(conn, "/v1/companies/#{company.id}", %{"inventory_valuation_method" => "LIFO"})
    post(conn, "/v1/stock/rebuild", %{})
    p = product(conn, goods)

    # LIFO: продадени 5 от последната партида (200) → остават 10@100 + 5@200 = 2000
    assert p["stock_value"] == "2000.00"
  end

  test "изписване на себестойност с правило", %{
    conn: conn,
    cp: cp,
    customer: customer,
    goods: goods,
    by_number: by_number
  } do
    # pair() търси offset == приходната сметка на артикула (както в ytbuch)
    post(conn, "/v1/stock/rules", %{
      "kind" => "goods",
      "inventory_account_id" => by_number["302"],
      "offset_account_id" => by_number["702"]
    })

    purchase(conn, cp, goods, 10, 100.0, "2026-01-01", "P-1")
    sale(conn, customer, goods, 4, "2026-01-05")

    conn = post(conn, "/v1/stock/writeoff", %{"month" => "2026-01"})
    body = json_response(conn, 200)
    assert body["amount"] == "400.00"
    assert length(body["entries"]) == 1

    entry = json_response(get(conn, "/v1/journal/#{hd(body["entries"])}"), 200)
    assert entry["document_type"] == "stock_writeoff"
    lines = Map.new(entry["lines"], &{&1["account_number"], &1})
    assert lines["702"]["direction"] == "debit"
    assert lines["702"]["amount"] == "400.00"
    assert lines["302"]["direction"] == "credit"

    # повторно пускане подменя записа
    conn = post(conn, "/v1/stock/writeoff", %{"month" => "2026-01"})
    assert length(json_response(conn, 200)["entries"]) == 1
  end

  test "без правила изписването спира", %{conn: conn, cp: cp, customer: customer, goods: goods} do
    purchase(conn, cp, goods, 10, 100.0, "2026-01-01", "P-1")
    sale(conn, customer, goods, 4, "2026-01-05")
    conn = post(conn, "/v1/stock/writeoff", %{"month" => "2026-01"})

    assert json_response(conn, 422)["detail"] ==
             "няма правила за склада — добавете ги в настройки, таб Склад"
  end

  test "наличност по обект и справка", %{conn: conn, company: company, cp: cp, goods: goods} do
    location =
      json_response(
        post(conn, "/v1/companies/#{company.id}/locations", %{"name" => "Склад"}),
        201
      )

    purchase(conn, cp, goods, 10, 100.0, "2026-01-01", "P-1")

    conn = get(conn, "/v1/inventory/at-location?location_id=0")
    body = json_response(conn, 200)
    assert body["count"] == 1
    assert hd(body["items"])["quantity"] == "10.0000"

    conn = get(conn, "/v1/stock/report?from=2026-01-01&to=2026-12-31")
    body = json_response(conn, 200)
    assert length(body["receipts"]) == 1
    assert length(body["balances"]) == 1
    _ = location
  end

  test "липсващо количество дава предупреждение", %{conn: conn, customer: customer, goods: goods} do
    sale(conn, customer, goods, 5, "2026-01-03")
    conn = post(conn, "/v1/stock/rebuild", %{})
    body = json_response(conn, 200)
    assert Enum.any?(body["warnings"], &String.contains?(&1, "липсват"))
  end
end

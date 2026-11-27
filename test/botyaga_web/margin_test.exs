defmodule BotyagaWeb.MarginTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("marg@baga.example", "МГ", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} =
      Companies.create(
        %{
          "name" => "МГ ООД",
          "eik" => "207666777",
          "accountant_name" => "Иван",
          "accountant_egn" => "8001010000"
        },
        user
      )

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})
    {:ok, conn: conn, company: company, by_number: by_number}
  end

  defp invoice(conn, cp, prod, dir, net, opts) do
    json_response(
      post(conn, "/v1/invoices", %{
        "direction" => dir,
        "number" => opts[:number],
        "issue_date" => "2026-11-10",
        "counterpart_id" => cp["id"],
        "is_margin" => 1,
        "lines" => [
          %{
            "product_id" => prod["id"],
            "description" => "автомобил",
            "quantity" => "1",
            "unit_price" => net,
            "vat_rate" => "0",
            "net_amount" => net,
            "vat_amount" => "0.00",
            "total_amount" => net
          }
        ]
      }),
      201
    )
  end

  test "марж: покупка колона 9, продажба без ДДС, протокол начислява ДДС върху маржа", %{
    conn: conn,
    by_number: bn
  } do
    car =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Авто VIN1",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => bn["304"]
        }),
        201
      )

    seller =
      json_response(
        post(conn, "/v1/counterparts", %{
          "name" => "BG дилър",
          "eik" => "333444555",
          "country" => "BG"
        }),
        201
      )

    buyer =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "111222333"}),
        201
      )

    buy = invoice(conn, seller, car, "in", "5800.00", number: "M-BUY")
    post(conn, "/v1/invoices/#{buy["id"]}/post", %{})
    sale = invoice(conn, buyer, car, "out", "8000.00", number: "M-SALE")
    post(conn, "/v1/invoices/#{sale["id"]}/post", %{})

    # покупката влиза в дневника за покупки, колона 9 (без ДДС)
    reg = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    p = Enum.find(reg["purchases"], &(&1["document_number"] == "M-BUY"))
    assert p["base_no_credit"] == "5800.00"
    assert p["vat_full_credit"] == "0.00"

    # продажбата по маржа влиза само с информативни колони (без суми)
    s = Enum.find(reg["sales"], &(&1["document_number"] == "M-SALE"))
    assert s["total_vat"] == "0.00"
    assert s["base_20"] == "0.00"

    # протокол за маржа
    pv = json_response(get(conn, "/v1/vat/margin/preview?month=2026-11"), 200)
    assert pv["errors"] == []
    assert hd(pv["lines"])["margin"] == "2200.00"
    assert pv["total_vat"] == "366.67"
    assert pv["total_base"] == "1833.33"

    pr = json_response(post(conn, "/v1/vat/margin", %{"month" => "2026-11"}), 201)
    assert pr["total_vat"] == "366.67"

    # статия Дт 702 / Кт 4532
    entry = json_response(get(conn, "/v1/journal/#{pr["journal_entry_id"]}"), 200)
    dirs = Enum.map(entry["lines"], &{&1["account_number"], &1["direction"], &1["amount"]})
    assert {"702", "debit", "366.67"} in dirs
    assert {"4532", "credit", "366.67"} in dirs

    # протоколът влиза в дневника за продажбите (колона 11/12)
    reg2 = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    m = Enum.find(reg2["sales"], &(&1["document_type"] == "09" and &1["base_20"] == "1833.33"))
    assert m["vat_20"] == "366.67"
  end

  test "отрицателен марж = нула, без ДДС", %{conn: conn, by_number: bn} do
    car =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Авто VIN2",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => bn["304"]
        }),
        201
      )

    seller =
      json_response(post(conn, "/v1/counterparts", %{"name" => "ФЛ", "is_individual" => 1}), 201)

    buyer =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент2", "eik" => "222333444"}),
        201
      )

    buy = invoice(conn, seller, car, "in", "5000.00", number: "M-BUY2")
    post(conn, "/v1/invoices/#{buy["id"]}/post", %{})
    sale = invoice(conn, buyer, car, "out", "4000.00", number: "M-SALE2")
    post(conn, "/v1/invoices/#{sale["id"]}/post", %{})

    pv = json_response(get(conn, "/v1/vat/margin/preview?month=2026-11"), 200)
    assert hd(pv["lines"])["margin"] == "-1000.00"
    assert pv["total_vat"] == "0.00"
  end
end

defmodule BotyagaWeb.VatTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("vat@baga.example", "ДДС", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(
        %{
          "name" => "ДДС ООД",
          "eik" => "207123456",
          "vat_number" => "BG207123456",
          "accountant_name" => "Иван Счетоводител",
          "accountant_egn" => "8001010000",
          "city" => "София",
          "post_code" => "1000",
          "street_name" => "Витоша",
          "building_number" => "1"
        },
        user
      )

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "111222333"}),
        201
      )

    supplier =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "222333444"}),
        201
      )

    service =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Консултация",
          "is_service" => true,
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    goods =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Материал",
          "product_type" => "10",
          "is_inventory" => true,
          "inventory_account_id" => by_number["302"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    sale =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "issue_date" => "2026-11-01",
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => service["id"],
              "description" => "Консултация",
              "quantity" => "10",
              "unit_price" => "100.00",
              "vat_rate" => "20",
              "net_amount" => "1000.00",
              "vat_amount" => "200.00",
              "total_amount" => "1200.00"
            }
          ]
        }),
        201
      )

    purchase =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => "IN-1",
          "issue_date" => "2026-11-02",
          "counterpart_id" => supplier["id"],
          "lines" => [
            %{
              "product_id" => goods["id"],
              "description" => "Материал",
              "quantity" => "5",
              "unit_price" => "50.00",
              "vat_rate" => "20",
              "net_amount" => "250.00",
              "vat_amount" => "50.00",
              "total_amount" => "300.00"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{sale["id"]}/post", %{})
    post(conn, "/v1/invoices/#{purchase["id"]}/post", %{})

    {:ok, conn: conn, company: company, by_number: by_number, cp: cp, service: service}
  end

  test "дневници и клетки за месеца", %{conn: conn} do
    conn = get(conn, "/v1/vat/registers?period=2026-11")
    body = json_response(conn, 200)

    assert body["period"] == "2026-11"
    assert body["period_nap"] == "202611"
    assert body["company_vat"] == "BG207123456"
    assert body["sales_count"] == 1
    assert body["purchase_count"] == 1
    assert body["cells"]["01-11"] == "1000.00"
    assert body["cells"]["01-21"] == "200.00"
    assert body["cells"]["01-31"] == "250.00"
    assert body["cells"]["01-41"] == "50.00"
    assert body["due"] == "150.00"
    assert body["refund"] == "0.00"
    assert length(body["sales"]) == 1
    assert length(body["purchases"]) == 1
    assert hd(body["sales"])["counterpart_vat_number"] == "111222333"
  end

  test "празен период и невалиден формат", %{conn: conn} do
    conn = get(conn, "/v1/vat/registers?period=2026-12")
    body = json_response(conn, 200)
    assert body["sales_count"] == 0
    assert body["due"] == "0.00"

    conn = get(conn, "/v1/vat/registers?period=")
    assert json_response(conn, 400)["detail"] == "period е задължителен (YYYY-MM)"

    conn = get(conn, "/v1/vat/registers?period=2026-13")
    assert json_response(conn, 400)["detail"] == "period трябва да е YYYY-MM или YYYYMM"
  end

  test "експорт на файлове за НАП", %{conn: conn} do
    conn = get(conn, "/v1/vat/export?period=202611&type=deklar")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=windows-1251"]
    assert get_resp_header(conn, "content-disposition") == [~s(attachment; filename="DEKLAR.TXT")]
    assert byte_size(response(conn, 200)) == 592

    conn = get(conn, "/v1/vat/export?period=202611&type=pokupki")
    assert byte_size(response(conn, 200)) == 276

    conn = get(conn, "/v1/vat/export?period=202611&type=prodagbi")
    assert byte_size(response(conn, 200)) == 426

    conn = get(conn, "/v1/vat/export?period=202611&type=zip")
    assert get_resp_header(conn, "content-type") == ["application/zip"]
    assert binary_part(response(conn, 200), 0, 4) == "PK\x03\x04"
  end

  test "клонът в POKUPKI и PRODAGBI е 0 по подразбиране", %{conn: conn, company: company} do
    for kind <- ["pokupki", "prodagbi"] do
      conn = get(conn, "/v1/vat/export?period=202611&type=#{kind}")
      assert binary_part(response(conn, 200), 21, 4) == "   0"
    end

    body = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    assert Enum.all?(body["purchases"], &(&1["branch"] == "0"))
    assert Enum.all?(body["sales"], &(&1["branch"] == "0"))

    patch(conn, "/v1/companies/#{company.id}", %{"vat_branch_number" => "2"})

    for kind <- ["pokupki", "prodagbi"] do
      conn = get(conn, "/v1/vat/export?period=202611&type=#{kind}")
      assert binary_part(response(conn, 200), 21, 4) == "   2"
    end

    body = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    assert Enum.all?(body["purchases"], &(&1["branch"] == "2"))
    assert Enum.all?(body["sales"], &(&1["branch"] == "2"))
  end

  test "декларацията се подписва с избраното лице", %{conn: conn, company: company} do
    patch(conn, "/v1/companies/#{company.id}", %{
      "vat_submitter" => "manager",
      "manager_egn" => "7001010000",
      "manager_name" => "Петър Управител"
    })

    conn = get(conn, "/v1/vat/export?period=202611&type=deklar")
    assert response(conn, 200) =~ "7001010000"
  end

  test "ръчни клетки", %{conn: conn} do
    conn =
      put(conn, "/v1/vat/manual?period=2026-11", %{
        "cell_33" => "0.5",
        "cell_70" => "10.00",
        "cell_80" => "5.00"
      })

    body = json_response(conn, 200)
    assert body["cells"]["01-33"] == "0.50"
    assert body["cells"]["01-70"] == "10.00"
    assert body["cells"]["01-80"] == "5.00"

    conn = put(conn, "/v1/vat/manual?period=2026-11", %{"cell_33" => "1.5"})
    assert json_response(conn, 422)["detail"] == "cell_33 трябва да е коефициент между 0 и 1"
  end

  test "VIES за контрагент от ЕС", %{conn: conn, service: service} do
    eu =
      json_response(
        post(conn, "/v1/counterparts", %{
          "name" => "EU Client",
          "vat_number" => "DE123456789",
          "country" => "DE"
        }),
        201
      )

    sale =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "issue_date" => "2026-11-05",
          "counterpart_id" => eu["id"],
          "vat_exemption_reason" => "VATEX-EU-IC",
          "lines" => [
            %{
              "product_id" => service["id"],
              "description" => "ВОД",
              "quantity" => "1",
              "unit_price" => "500.00",
              "vat_rate" => "0",
              "net_amount" => "500.00",
              "vat_amount" => "0.00",
              "total_amount" => "500.00"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{sale["id"]}/post", %{})

    conn = get(conn, "/v1/vat/registers?period=2026-11")
    body = json_response(conn, 200)
    assert body["cells"]["01-15"] == "500.00"
    assert [party] = body["vies"]
    assert party["vat_number"] == "DE123456789"
    assert party["country"] == "DE"
    assert party["base_vod"] == "500.00"

    conn = get(conn, "/v1/vat/export?period=202611&type=vies")
    assert response(conn, 200) =~ "VHR"
    assert response(conn, 200) =~ "DE123456789"
  end

  test "основания за неначисляване", %{conn: conn} do
    conn = get(conn, "/v1/vat-exemptions?search=export")
    body = json_response(conn, 200)
    assert body["count"] > 0
    assert Enum.any?(body["items"], &(&1["code"] == "VATEX-EU-G"))
  end
end

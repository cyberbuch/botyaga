defmodule BotyagaWeb.VatRegistersTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("vatreg@baga.example", "ДДС", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(
        %{
          "name" => "Регистри ООД",
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

    supplier =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "222333444"}),
        201
      )

    product =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["302"]
        }),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => "IN-PROT-1",
          "issue_date" => "2026-11-03",
          "counterpart_id" => supplier["id"],
          "exclude_vat" => 1,
          "lines" => [
            line(product["id"], "Стока", "1000.00")
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

    proto =
      json_response(post(conn, "/v1/invoices/#{inv["id"]}/issue-protocol", %{}), 201)

    post(conn, "/v1/invoices/#{proto["id"]}/post", %{})

    {:ok, conn: conn, supplier: supplier, product: product}
  end

  defp line(product_id, description, amount) do
    %{
      "product_id" => product_id,
      "description" => description,
      "quantity" => "1",
      "unit_price" => amount,
      "vat_rate" => "0",
      "net_amount" => amount,
      "vat_amount" => "0.00",
      "total_amount" => amount
    }
  end

  test "протоколът по чл. 117 влиза в двата дневника", %{conn: conn} do
    body = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)

    assert body["purchase_count"] == 1
    assert body["sales_count"] == 1
    assert [purch] = body["purchases"]
    assert purch["document_type"] == "09"
    assert purch["base_full_credit"] == "1000.00"
    assert purch["vat_full_credit"] == "200.00"
    assert [sale] = body["sales"]
    assert sale["document_type"] == "09"
    assert sale["vop_sales_base"] == "1000.00"
    assert sale["vop_sales_vat"] == "200.00"
    assert body["cells"]["01-12"] == "1000.00"
    assert body["cells"]["01-22"] == "200.00"
    assert body["cells"]["01-31"] == "1000.00"
    assert body["cells"]["01-41"] == "200.00"
  end

  test "фактурата извън ДДС дневника не влиза в регистрите", %{conn: conn} do
    body = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    refute Enum.any?(body["purchases"], &(&1["document_number"] == "IN-PROT-1"))
  end

  test "митническата декларация влиза в дневника на покупките", %{
    conn: conn,
    supplier: supplier,
    product: product
  } do
    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => "IN-CUS-1",
          "issue_date" => "2026-12-03",
          "counterpart_id" => supplier["id"],
          "exclude_vat" => 1,
          "lines" => [line(product["id"], "Стока", "1000.00")]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

    cust =
      json_response(
        post(conn, "/v1/invoices/#{inv["id"]}/issue-customs", %{
          "number" => "MRN-1",
          "customs_duty" => "50.00"
        }),
        201
      )

    post(conn, "/v1/invoices/#{cust["id"]}/post", %{})

    body = json_response(get(conn, "/v1/vat/registers?period=2026-12"), 200)
    assert body["purchase_count"] == 1
    assert body["sales_count"] == 0
    assert [purch] = body["purchases"]
    assert purch["document_type"] == "07"
    assert purch["base_full_credit"] == "1050.00"
    assert purch["vat_full_credit"] == "210.00"
    assert body["cells"]["01-31"] == "1050.00"
    assert body["cells"]["01-41"] == "210.00"
  end
end

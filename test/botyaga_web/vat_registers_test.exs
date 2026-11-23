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

  test "печат на дневниците: xlsx/ods са ZIP файлове, pdf без sidecar → 503, лош формат → 400", %{
    conn: conn
  } do
    conn = get(conn, "/v1/vat/export?period=2026-11&type=print&register=purchases&format=xlsx")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "spreadsheetml.sheet"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "dnevnik-pokupki-202611.xlsx"
    assert binary_part(conn.resp_body, 0, 2) == "PK"
    assert :binary.match(conn.resp_body, "xl/worksheets/sheet1.xml") != :nomatch

    conn = get(conn, "/v1/vat/export?period=2026-11&type=print&register=sales&format=ods&bg=1")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "opendocument.spreadsheet"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "dnevnik-prodagbi-202611.ods"
    assert binary_part(conn.resp_body, 0, 2) == "PK"
    assert :binary.match(conn.resp_body, "content.xml") != :nomatch

    # в тестова среда няма print sidecar → pdf връща 503, а не 500
    conn = get(conn, "/v1/vat/export?period=2026-11&type=print&register=sales&format=pdf")
    assert json_response(conn, 503)

    conn = get(conn, "/v1/vat/export?period=2026-11&type=print&register=sales&format=csv")
    assert json_response(conn, 400)
  end

  test "файловете за НАП са с фиксирана ширина и Windows-1251 (като референтните в secret/VAT)",
       %{
         conn: conn
       } do
    # ширините са без CRLF (редът се дели на \r\n): 274/424/590 байта в cp1251
    for {type, name, width} <- [
          {"pokupki", "POKUPKI.TXT", 274},
          {"prodagbi", "PRODAGBI.TXT", 424},
          {"deklar", "DEKLAR.TXT", 590}
        ] do
      conn = get(conn, "/v1/vat/export?period=2026-11&type=#{type}")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "windows-1251"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ name

      for line <- String.split(conn.resp_body, "\r\n", trim: true) do
        assert byte_size(line) == width
      end
    end

    # ZIP съдържа трите файла
    conn = get(conn, "/v1/vat/export?period=2026-11&type=zip")
    assert conn.status == 200

    for f <- ["DEKLAR.TXT", "POKUPKI.TXT", "PRODAGBI.TXT"] do
      assert :binary.match(conn.resp_body, f) != :nomatch
    end
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

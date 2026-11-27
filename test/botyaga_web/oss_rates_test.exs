defmodule BotyagaWeb.OssRatesTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("osr@baga.example", "ОСР", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "ОСР ООД", "eik" => "207444555"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    {:ok, conn: conn, company: company}
  end

  test "физическо лице: без ЕИК/ДДС, само име/адрес/държава", %{conn: conn} do
    cp =
      json_response(
        post(conn, "/v1/counterparts", %{
          "name" => "Hans Steiner",
          "is_individual" => 1,
          "country" => "DE",
          "address" => "Berlin"
        }),
        201
      )

    assert cp["is_individual"] == 1
    assert cp["eik"] in ["", nil]
    assert cp["vat_number"] in ["", nil]
  end

  test "OSS ставки: история и аналитична сметка по държава", %{conn: conn, company: company} do
    patch(conn, "/v1/companies/#{company.id}", %{"oss_enabled" => 1})

    r1 =
      json_response(
        post(conn, "/v1/oss/rates", %{
          "country" => "DE",
          "account_number" => "453401",
          "rate" => "19",
          "valid_from" => "2026-01-01"
        }),
        201
      )

    assert r1["account_number"] == "453401"

    # нова ставка от 30-06-2026 (копиран ред) — историята се пази
    r2 =
      json_response(
        post(conn, "/v1/oss/rates/#{r1["id"]}/copy", %{
          "rate" => "16",
          "valid_from" => "2026-06-30"
        }),
        201
      )

    assert r2["rate"] == "16"

    rates = json_response(get(conn, "/v1/oss/rates"), 200)["items"]
    assert length(rates) == 2

    # resolve към дата връща последната валидна
    assert Botyaga.Oss.Rates.resolve(company.id, "DE", "2026-05-01").rate == "19"
    assert Botyaga.Oss.Rates.resolve(company.id, "DE", "2026-07-01").rate == "16"
  end

  test "OSS фактура (кредитно/дебитно/отчет) ползва аналитичната сметка по държава", %{
    conn: conn,
    company: company
  } do
    patch(conn, "/v1/companies/#{company.id}", %{"oss_enabled" => 1})
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    bn = Map.new(accounts, &{&1["number"], &1["id"]})

    json_response(
      post(conn, "/v1/oss/rates", %{
        "country" => "DE",
        "account_number" => "453401",
        "rate" => "19",
        "valid_from" => "2026-01-01"
      }),
      201
    )

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{
          "name" => "Hans",
          "is_individual" => 1,
          "country" => "DE"
        }),
        201
      )

    prod =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => false
        }),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => "OSS-1",
          "issue_date" => "2026-11-10",
          "counterpart_id" => cp["id"],
          "is_oss" => 1,
          "oss_country" => "DE",
          "lines" => [
            %{
              "product_id" => prod["id"],
              "description" => "дистанционна",
              "quantity" => "1",
              "unit_price" => "100.00",
              "vat_rate" => "19",
              "net_amount" => "100.00",
              "vat_amount" => "19.00",
              "total_amount" => "119.00"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
    entry = json_response(get(conn, "/v1/journal/#{shown["journal_entry_id"]}"), 200)
    nums = Enum.map(entry["lines"], & &1["account_number"])
    assert "453401" in nums
    _ = bn
  end
end

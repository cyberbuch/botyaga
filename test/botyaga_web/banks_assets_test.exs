defmodule BotyagaWeb.BanksAssetsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("ba@baga.example", "Банки", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Банки ООД", "eik" => "207123456", "currency" => "EUR"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})
    {:ok, conn: conn, company: company, by_number: by_number}
  end

  describe "банкови сметки" do
    test "създаване, дубликат по IBAN и валута по подразбиране", %{
      conn: conn,
      by_number: by_number
    } do
      conn =
        post(conn, "/v1/bank-accounts", %{
          "name" => "Основна",
          "iban" => "BG80BNBG96611020345678",
          "bic" => "BNBGBGSD",
          "balance" => "1000.00",
          "gl_account_id" => by_number["501"]
        })

      body = json_response(conn, 201)
      assert body["currency"] == "EUR"
      assert body["balance"] == "1000.00"
      assert body["gl_account_code"] == "501"

      conn =
        post(conn, "/v1/bank-accounts", %{"name" => "Друга", "iban" => "BG80BNBG96611020345678"})

      assert json_response(conn, 409)["detail"] == "IBAN вече съществува"

      conn = post(conn, "/v1/bank-accounts", %{"name" => "Без IBAN"})
      assert json_response(conn, 422)["detail"] == "iban е задължително"
    end

    test "редакция и триене", %{conn: conn} do
      account =
        json_response(
          post(conn, "/v1/bank-accounts", %{
            "name" => "За триене",
            "iban" => "BG11111111111111111111"
          }),
          201
        )

      conn =
        patch(conn, "/v1/bank-accounts/#{account["id"]}", %{
          "balance" => "500.50",
          "bank_name" => "Пощенска"
        })

      body = json_response(conn, 200)
      assert body["balance"] == "500.50"
      assert body["bank_name"] == "Пощенска"

      conn = delete(conn, "/v1/bank-accounts/#{account["id"]}")
      assert response(conn, 204)
    end
  end

  describe "ДМА" do
    test "категории и актив", %{conn: conn} do
      category =
        json_response(
          post(conn, "/v1/fixed-asset-categories", %{
            "name" => "Компютри",
            "min_depreciation_rate" => "20",
            "max_depreciation_rate" => "50"
          }),
          201
        )

      assert category["min_depreciation_rate"] == "20.0000"

      conn =
        post(conn, "/v1/fixed-assets", %{
          "name" => "Лаптоп",
          "category_id" => category["id"],
          "cost" => "2400.00",
          "salvage_value" => "0.00",
          "accounting_depreciation_rate" => "20",
          "depreciation_method" => "linear",
          "acquisition_date" => "2026-01-01",
          "put_into_service_date" => "2026-01-01"
        })

      body = json_response(conn, 201)
      assert body["cost"] == "2400.00"
      assert body["accumulated_depreciation"] == "0.00"
      assert body["status"] == "active"
      assert body["category_id"] == category["id"]
    end

    test "амортизация: преглед и пост Дт 603 / Кт 241", %{conn: conn} do
      category =
        json_response(post(conn, "/v1/fixed-asset-categories", %{"name" => "Машини"}), 201)

      post(conn, "/v1/fixed-assets", %{
        "name" => "Машина",
        "category_id" => category["id"],
        "cost" => "1200.00",
        "accounting_depreciation_rate" => "20",
        "depreciation_method" => "linear"
      })

      conn = post(conn, "/v1/fixed-assets/depreciation/preview", %{})
      body = json_response(conn, 200)
      assert body["total_amount"] == "20.00"
      assert hd(body["items"])["monthly_amount"] == "20.00"

      conn = post(conn, "/v1/fixed-assets/depreciation/post", %{"period" => "2026-02"})
      body = json_response(conn, 201)
      assert body["document_type"] == "depreciation"
      assert body["total_amount"] == "20.00"

      entry = json_response(get(conn, "/v1/journal/#{body["id"]}"), 200)
      lines = Map.new(entry["lines"], &{&1["account_number"], &1})
      assert lines["603"]["direction"] == "debit"
      assert lines["603"]["amount"] == "20.00"
      assert lines["241"]["direction"] == "credit"

      asset = hd(json_response(get(conn, "/v1/fixed-assets"), 200)["items"])
      assert asset["accumulated_depreciation"] == "20.00"
      assert asset["tax_accumulated_depreciation"] == "20.00"
    end

    test "събития: преоценка, местене, консервация, отписване", %{conn: conn, company: company} do
      location =
        json_response(
          post(conn, "/v1/companies/#{company.id}/locations", %{"name" => "Склад"}),
          201
        )

      asset =
        json_response(
          post(conn, "/v1/fixed-assets", %{"name" => "Актив", "cost" => "1000.00"}),
          201
        )

      conn =
        post(conn, "/v1/fixed-assets/#{asset["id"]}/revalue", %{
          "new_value" => "1500.00",
          "event_date" => "2026-03-01",
          "reason" => "Пазарна"
        })

      assert json_response(conn, 200)["cost"] == "1500.00"

      conn =
        post(conn, "/v1/fixed-assets/#{asset["id"]}/move", %{
          "location_id" => location["id"],
          "event_date" => "2026-03-02"
        })

      assert json_response(conn, 200)["location_id"] == location["id"]

      conn =
        post(conn, "/v1/fixed-assets/#{asset["id"]}/conserve", %{"event_date" => "2026-03-03"})

      assert json_response(conn, 200)["is_conserved"] == 1

      conn = post(conn, "/v1/fixed-assets/#{asset["id"]}/end-conserve", %{})
      assert json_response(conn, 200)["is_conserved"] == 0

      conn =
        post(conn, "/v1/fixed-assets/#{asset["id"]}/dispose", %{
          "disposal_type" => "sale",
          "sale_amount" => "200.00"
        })

      assert json_response(conn, 200)["status"] == "sold"

      events = json_response(get(conn, "/v1/fixed-assets/#{asset["id"]}/events"), 200)["items"]

      assert Enum.map(events, & &1["event_type"]) == [
               "revaluation",
               "movement",
               "conservation_start",
               "conservation_end",
               "disposal"
             ]
    end

    test "консервиран актив не се амортизира", %{conn: conn} do
      asset =
        json_response(
          post(conn, "/v1/fixed-assets", %{
            "name" => "Спрян",
            "cost" => "1000.00",
            "accounting_depreciation_rate" => "20"
          }),
          201
        )

      post(conn, "/v1/fixed-assets/#{asset["id"]}/conserve", %{})

      body = json_response(post(conn, "/v1/fixed-assets/depreciation/preview", %{}), 200)
      assert body["total_amount"] == "0.00"
    end
  end
end

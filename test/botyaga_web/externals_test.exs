defmodule BotyagaWeb.ExternalsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies, Repo}
  alias Botyaga.Rates.Rate

  setup do
    {:ok, user} =
      Accounts.create_user("ext@baga.example", "Външни", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Външни ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)

    Repo.insert!(%Rate{code: "USD", rate: "1.08", date: "2026-01-15"})
    Repo.insert!(%Rate{code: "BGN", rate: "1.95583", date: "2026-01-15"})
    Repo.insert!(%Rate{code: "USD", rate: "1.07", date: "2026-01-14"})

    {:ok, conn: conn, company: company}
  end

  describe "exchange-rates" do
    test "index по дата и последна дата", %{conn: conn} do
      body = json_response(get(conn, "/v1/exchange-rates?date=2026-01-15"), 200)
      assert body["date"] == "2026-01-15"
      assert body["base"] == "EUR"
      assert body["items"] |> Enum.map(& &1["currency_code"]) == ["BGN", "USD"]

      latest = json_response(get(conn, "/v1/exchange-rates"), 200)
      assert latest["date"] == "2026-01-15"
    end

    test "rate и cross", %{conn: conn} do
      r = json_response(get(conn, "/v1/exchange-rates/rate?currency=USD&date=2026-01-15"), 200)
      assert r["rate"] == "1.08"
      assert r["base"] == "EUR"

      c =
        json_response(get(conn, "/v1/exchange-rates/cross?from=USD&to=BGN&date=2026-01-15"), 200)

      assert c["rate"] == "1.810954"
      assert c["rate_date"] == "2026-01-15"
    end

    test "as-of към по-ранна дата", %{conn: conn} do
      r = json_response(get(conn, "/v1/exchange-rates/rate?currency=USD&date=2026-01-16"), 200)
      assert r["date"] == "2026-01-15"
      assert r["rate"] == "1.08"
    end

    test "грешки при липсващи полета", %{conn: conn} do
      conn = get(conn, "/v1/exchange-rates/rate?date=2026-01-15")
      assert json_response(conn, 400)["detail"] == "currency е задължителен"

      conn = get(conn, "/v1/exchange-rates/rate?currency=USD")
      assert json_response(conn, 400)["detail"] == "date е задължителен (YYYY-MM-DD)"

      conn = get(conn, "/v1/exchange-rates/rate?currency=JPY&date=2026-01-15")
      assert json_response(conn, 404)["detail"] == "няма курс за тази валута"
    end

    test "import с невалиден mode", %{conn: conn} do
      conn = post(conn, "/v1/exchange-rates/import", %{"mode" => "bogus"})
      assert json_response(conn, 422)["detail"] == "mode трябва да е daily или history"
    end
  end

  describe "addresses/parse" do
    test "локално разбиване без Mistral ключ", %{conn: conn} do
      body =
        json_response(
          post(conn, "/v1/addresses/parse", %{"address" => "ул. Витоша 15, 1000 София"}),
          200
        )

      assert body["parse_ok"] == true
      assert body["city"] == "София"
      assert body["region"] == "BG-22"
      assert body["street_name"] == "Витоша"
      assert body["parse_note"] =~ "локално"
    end

    test "address е задължителен", %{conn: conn} do
      conn = post(conn, "/v1/addresses/parse", %{})
      assert json_response(conn, 422)["detail"] == "address е задължително"
    end
  end

  describe "scans/extract" do
    test "без Mistral ключ връща 422", %{conn: conn} do
      conn = post(conn, "/v1/scans/extract", %{"content_base64" => "QUJD"})
      assert json_response(conn, 422)["detail"] =~ "Няма Mistral ключ"
    end

    test "валидация на полетата", %{conn: conn} do
      conn = post(conn, "/v1/scans/extract", %{})
      assert json_response(conn, 422)["detail"] == "content_base64 е задължително"

      conn =
        post(conn, "/v1/scans/extract", %{"content_base64" => "QUJD", "direction" => "bogus"})

      assert json_response(conn, 422)["detail"] == "direction must be 'in' or 'out'"
    end
  end

  describe "VIES" do
    test "невалиден ДДС номер", %{conn: conn} do
      conn = get(conn, "/v1/counterparts/vies-lookup?vat=US123")
      assert json_response(conn, 422)["detail"] =~ "vat трябва да е ЕС ДДС номер"

      conn = post(conn, "/v1/counterparts/vies", %{"vat_number" => "US123"})
      assert json_response(conn, 422)["detail"] =~ "vat_number трябва да е ЕС ДДС номер"
    end
  end
end

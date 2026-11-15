defmodule BotyagaWeb.CatalogTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, superadmin} =
      Accounts.create_user("cat@baga.example", "Каталог", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Каталог ООД", "eik" => "207123456"}, superadmin)

    Companies.set_active(superadmin.username, company.id)
    {:ok, conn: auth_conn(build_conn(), superadmin), company: company, user: superadmin}
  end

  describe "сметкоплан" do
    test "списъкът е по номер и носи is_currency като булева", %{conn: conn, company: company} do
      conn = get(conn, "/v1/accounts?limit=500")
      body = json_response(conn, 200)
      assert body["total"] == 360
      assert body["count"] == 360
      assert hd(body["items"])["number"] == "101"
      assert is_boolean(hd(body["items"])["is_currency"])

      # _seed-ът не пипа is_currency — както в ytbuch; флагът идва при ръчен запис.
      account = Enum.find(body["items"], &(&1["number"] == "411"))
      assert account["is_currency"] == false
      assert Companies.get_company(company.id).name == "Каталог ООД"
    end

    test "създаване, дубликат и валидации", %{conn: conn} do
      conn = post(conn, "/v1/accounts", %{"number" => "9999", "name" => "Тестова"})
      assert json_response(conn, 201)["number"] == "9999"
      assert json_response(conn, 201)["is_currency"] == false

      conn = post(conn, "/v1/accounts", %{"number" => "4111", "name" => "Валутна"})
      assert json_response(conn, 201)["is_currency"] == true

      conn = post(conn, "/v1/accounts", %{"number" => "9999", "name" => "Друга"})
      assert json_response(conn, 409)["detail"] == "номерът вече съществува"

      conn = post(conn, "/v1/accounts", %{"name" => "Без номер"})
      assert json_response(conn, 422)["detail"] == "number е задължително"

      conn =
        post(conn, "/v1/accounts", %{
          "number" => "9998",
          "name" => "X",
          "analytic_type" => "грешен"
        })

      assert json_response(conn, 422)["detail"] == "analytic_type е none, counterpart или product"
    end

    test "seed не дублира и връща броя", %{conn: conn} do
      conn = post(conn, "/v1/accounts/seed-saft", %{})
      body = json_response(conn, 200)
      assert body["created"] == 0
      assert body["skipped"] == 360
      assert body["total"] == 360
    end

    test "редакция и триене", %{conn: conn} do
      conn = post(conn, "/v1/accounts", %{"number" => "9997", "name" => "За редакция"})
      id = json_response(conn, 201)["id"]

      conn = patch(conn, "/v1/accounts/#{id}", %{"name" => "Редактирана"})
      assert json_response(conn, 200)["name"] == "Редактирана"

      conn = delete(conn, "/v1/accounts/#{id}")
      assert response(conn, 204)

      conn = get(conn, "/v1/accounts/#{id}")
      assert json_response(conn, 404)["detail"] == "сметката не е намерена"
    end
  end

  describe "контрагенти" do
    test "създаване с изведен ЕИК от ДДС номера", %{conn: conn} do
      conn =
        post(conn, "/v1/counterparts", %{
          "name" => "Клиент Демо",
          "vat_number" => "bg207123456",
          "counterpart_type" => "customer"
        })

      body = json_response(conn, 201)
      assert body["vat_number"] == "BG207123456"
      assert body["eik"] == "207123456"
      assert body["country"] == "BG"
      assert body["counterpart_type"] == "customer"
    end

    test "чужд контрагент получава 999999999", %{conn: conn} do
      conn = post(conn, "/v1/counterparts", %{"name" => "Foreign Ltd", "country" => "US"})
      assert json_response(conn, 201)["eik"] == "999999999"
    end

    test "дубликат по ЕИК и по ДДС", %{conn: conn} do
      conn = post(conn, "/v1/counterparts", %{"name" => "Първи", "eik" => "111222333"})
      assert response(conn, 201)

      conn = post(conn, "/v1/counterparts", %{"name" => "Втори", "eik" => "111222333"})
      assert json_response(conn, 409)["detail"] == "контрагент с този ЕИК вече съществува"

      conn = post(conn, "/v1/counterparts", %{"name" => "С ДДС", "vat_number" => "BG444555666"})
      assert response(conn, 201)

      conn =
        post(conn, "/v1/counterparts", %{
          "name" => "Трети",
          "eik" => "999888777",
          "vat_number" => "BG444555666"
        })

      assert json_response(conn, 409)["detail"] == "контрагент с този ДДС номер вече съществува"

      conn = post(conn, "/v1/counterparts", %{"name" => "Еднократен", "eik" => "999999999"})
      assert response(conn, 201)
    end

    test "валидации на типа, адреса и областта", %{conn: conn} do
      conn = post(conn, "/v1/counterparts", %{})
      assert json_response(conn, 422)["detail"] == "name е задължително"

      conn = post(conn, "/v1/counterparts", %{"name" => "X", "counterpart_type" => "грешен"})

      assert json_response(conn, 422)["detail"] ==
               "counterpart_type е customer, supplier или both"

      conn = post(conn, "/v1/counterparts", %{"name" => "X", "address_type" => "грешен"})

      assert json_response(conn, 422)["detail"] ==
               "address_type е StreetAddress, PostalAddress, BillingAddress, ShipToAddress или ShipFromAddress"

      conn = post(conn, "/v1/counterparts", %{"name" => "X", "region" => "BG-99"})
      assert json_response(conn, 422)["detail"] == "region трябва да е код BG-01 … BG-28"

      conn = post(conn, "/v1/counterparts", %{"name" => "X", "region" => "София"})
      assert json_response(conn, 201)["region"] == "BG-22"
    end

    test "редакция и триене", %{conn: conn} do
      conn = post(conn, "/v1/counterparts", %{"name" => "За триене", "eik" => "444555666"})
      id = json_response(conn, 201)["id"]

      conn = patch(conn, "/v1/counterparts/#{id}", %{"city" => "Пловдив"})
      assert json_response(conn, 200)["city"] == "Пловдив"

      conn = delete(conn, "/v1/counterparts/#{id}")
      assert response(conn, 204)
    end
  end

  describe "стоки" do
    test "авто-код и услуга нулира склада", %{conn: conn} do
      conn =
        post(conn, "/v1/products", %{
          "name" => "Консултация",
          "is_service" => true,
          "price" => "100.00"
        })

      body = json_response(conn, 201)
      assert body["code"] == "1"
      assert body["is_service"] == 1
      assert body["is_inventory"] == 0
      assert body["stock_quantity"] == "0"
      assert body["cn8_code"] == "00000000"
      assert body["product_type"] == ""
      assert body["unit"] == "C62"
      assert body["vat_rate"] == "20"

      conn = post(conn, "/v1/products", %{"name" => "Втора услуга", "is_service" => true})
      assert json_response(conn, 201)["code"] == "2"
    end

    test "вид 10 попълва 302/706/601", %{conn: conn} do
      conn =
        post(conn, "/v1/products", %{
          "name" => "Цимент",
          "product_type" => "10",
          "is_inventory" => true
        })

      body = json_response(conn, 201)
      assert body["is_inventory"] == 1

      accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
      by_number = Map.new(accounts, &{&1["number"], &1["id"]})
      assert body["inventory_account_id"] == by_number["302"]
      assert body["revenue_account_id"] == by_number["706"]
      assert body["expense_account_id"] == by_number["601"]
    end

    test "автоматичното изписване иска валидни сметки", %{conn: conn} do
      conn =
        post(conn, "/v1/products", %{
          "name" => "Материал",
          "product_type" => "10",
          "is_inventory" => true,
          "auto_write_off" => true,
          "inventory_account_id" => 99_999_999
        })

      assert json_response(conn, 404)["detail"] == "сметката не е намерен"

      conn =
        post(conn, "/v1/products", %{
          "name" => "Материал 2",
          "product_type" => "10",
          "is_inventory" => true,
          "auto_write_off" => true
        })

      body = json_response(conn, 201)
      assert body["auto_write_off"] == 1
      assert body["inventory_account_id"] > 0
      assert body["expense_account_id"] > 0
    end

    test "дубликат по код и редакция пази количеството", %{conn: conn} do
      conn = post(conn, "/v1/products", %{"name" => "Стока", "code" => "ST-1"})
      id = json_response(conn, 201)["id"]

      conn = post(conn, "/v1/products", %{"name" => "Друга", "code" => "st-1"})
      assert json_response(conn, 409)["detail"] == "артикул с този код вече съществува"

      conn = patch(conn, "/v1/products/#{id}", %{"price" => "55.00"})
      body = json_response(conn, 200)
      assert body["price"] == "55.00"
      assert body["stock_quantity"] == "0"

      conn = delete(conn, "/v1/products/#{id}")
      assert response(conn, 204)
    end
  end

  describe "номенклатури" do
    test "видовете са 12", %{conn: conn} do
      body = json_response(get(conn, "/v1/saft/nomenclatures"), 200)
      assert body["count"] == 12
      assert Enum.any?(body["kinds"], &(&1["id"] == "accounts"))
    end

    test "непознат вид е 400", %{conn: conn} do
      conn = get(conn, "/v1/saft/nomenclatures?kind=нещо")
      assert json_response(conn, 400)["detail"] == "непозната номенклатура (kind)"
    end

    test "сметките и мерните единици се търсят", %{conn: conn} do
      body = json_response(get(conn, "/v1/saft/nomenclatures?kind=accounts&search=клиенти"), 200)
      assert body["count"] > 0
      assert Enum.all?(body["items"], &Map.has_key?(&1, "code"))

      body = json_response(get(conn, "/v1/units?search=килограм"), 200)
      assert body["count"] > 0
      assert Enum.any?(body["items"], &(&1["code"] == "KGM"))
      assert body["limit"] == 50
    end

    test "КН8 търси по код и описание", %{conn: conn} do
      body =
        json_response(get(conn, "/v1/saft/nomenclatures?kind=cn8&search=лаптоп&limit=5"), 200)

      assert body["count"] > 0
      assert hd(body["items"])["code"] == "84713000"
    end
  end

  describe "КН8 предложение" do
    test "услуга и стока", %{conn: conn} do
      conn =
        post(conn, "/v1/products/cn8-suggest", %{
          "name" => "Счетоводно обслужване",
          "is_service" => true
        })

      body = json_response(conn, 200)
      assert body["cn8_code"] == "00000000"
      assert body["is_service"] == true
      assert body["product_type"] == ""
      assert body["source"] == "catalog"
      assert length(body["candidates"]) > 0

      conn = post(conn, "/v1/products/cn8-suggest", %{"name" => "Лаптоп Lenovo ThinkPad"})
      body = json_response(conn, 200)
      assert body["cn8_code"] == "84713000"
      assert body["unit"] == "H87"
    end

    test "празно име и описание е 422", %{conn: conn} do
      conn = post(conn, "/v1/products/cn8-suggest", %{})
      assert json_response(conn, 422)["detail"] == "въведете име или описание на артикула"
    end
  end

  test "потребител без фирма получава 403", %{company: company} do
    {:ok, other} = Accounts.create_user("other@baga.example", "Друг", "парола-123")
    conn = auth_conn(build_conn(), other) |> get("/v1/accounts")
    assert json_response(conn, 403)["detail"] == "нямате достъп до фирма"
    assert company.id > 0
  end
end

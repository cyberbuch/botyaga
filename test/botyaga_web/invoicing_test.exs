defmodule BotyagaWeb.InvoicingTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("inv@baga.example", "Фактури", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Фактури ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)

    post(conn, "/v1/companies/#{company.id}/document-series", %{
      "name" => "Фактури",
      "document_types" => ~w(01 02 03)
    })

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент Демо", "eik" => "111222333"}),
        201
      )

    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

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

    {:ok,
     conn: conn,
     company: company,
     cp_id: cp["id"],
     service_id: service["id"],
     goods_id: goods["id"],
     by_number: by_number}
  end

  defp sale_line(service_id, attrs \\ %{}) do
    Map.merge(
      %{
        "product_id" => service_id,
        "description" => "Консултация",
        "quantity" => "10",
        "unit" => "HUR",
        "unit_price" => "100.00",
        "vat_rate" => "20",
        "net_amount" => "1000.00",
        "vat_amount" => "200.00",
        "total_amount" => "1200.00"
      },
      attrs
    )
  end

  describe "чернови" do
    test "изходяща фактура взима номер от серията и сумира редовете", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      conn =
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "issue_date" => "2026-11-01",
          "counterpart_id" => cp_id,
          "lines" => [sale_line(service_id)]
        })

      body = json_response(conn, 201)
      assert body["number"] == "0000000001"
      assert body["status"] == "draft"
      assert body["net_amount"] == "1000.00"
      assert body["vat_amount"] == "200.00"
      assert body["total_amount"] == "1200.00"
      assert body["accounting_month"] == "2026-11"
      assert length(body["lines"]) == 1
      assert body["counterpart"]["name"] == "Клиент Демо"
      assert body["company"]["name"] == "Фактури ООД"
    end

    test "входяща фактура иска номер", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      conn =
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "issue_date" => "2026-11-01",
          "counterpart_id" => cp_id,
          "lines" => [sale_line(service_id)]
        })

      assert json_response(conn, 422)["detail"] == "номерът на входящия документ е задължителен"
    end

    test "дубликат входящ номер от същия доставчик", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      body = %{
        "direction" => "in",
        "issue_date" => "2026-11-01",
        "counterpart_id" => cp_id,
        "number" => "IN-1",
        "lines" => [sale_line(service_id)]
      }

      assert response(post(conn, "/v1/invoices", body), 201)
      conn = post(conn, "/v1/invoices", body)

      assert json_response(conn, 409)["detail"] ==
               "входящ документ с този номер от този доставчик вече съществува"
    end

    test "кредитно известие иска оригинал и обръща знака", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      conn =
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "document_type" => "03",
          "issue_date" => "2026-11-02",
          "counterpart_id" => cp_id,
          "lines" => [sale_line(service_id)]
        })

      assert json_response(conn, 422)["detail"] ==
               "известието трябва да сочи към първоначална фактура"

      original =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      conn =
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "document_type" => "03",
          "issue_date" => "2026-11-02",
          "counterpart_id" => cp_id,
          "original_invoice_id" => original["id"],
          "lines" => [sale_line(service_id)]
        })

      body = json_response(conn, 201)
      assert body["total_amount"] == "-1200.00"
      assert hd(body["lines"])["net_amount"] == "-1000.00"
    end

    test "невалидни полета", %{conn: conn, cp_id: cp_id} do
      conn =
        post(conn, "/v1/invoices", %{
          "direction" => "странична",
          "issue_date" => "2026-11-01",
          "counterpart_id" => cp_id
        })

      assert json_response(conn, 422)["detail"] == "direction must be 'in' or 'out'"

      conn = post(conn, "/v1/invoices", %{"direction" => "out", "counterpart_id" => cp_id})
      assert json_response(conn, 422)["detail"] == "issue_date е задължително"

      conn = post(conn, "/v1/invoices", %{"direction" => "out", "issue_date" => "2026-11-01"})
      assert json_response(conn, 422)["detail"] == "counterpart_id е задължително"
    end

    test "следващ номер и редакция", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      body = %{
        "direction" => "out",
        "issue_date" => "2026-11-01",
        "counterpart_id" => cp_id,
        "lines" => [sale_line(service_id)]
      }

      first = json_response(post(conn, "/v1/invoices", body), 201)

      next =
        json_response(get(conn, "/v1/invoices/next-number?document_type=01&direction=out"), 200)

      assert next["number"] == "0000000002"

      conn = patch(conn, "/v1/invoices/#{first["id"]}", %{"notes" => "Бележка"})
      assert json_response(conn, 200)["notes"] == "Бележка"

      conn = delete(conn, "/v1/invoices/#{first["id"]}")
      assert response(conn, 204)
    end
  end

  describe "пост" do
    test "продажба: Дт 411 / Кт 702 / Кт 4532", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      conn = post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      body = json_response(conn, 201)
      assert body["vat_type"] == "sales"

      lines = Map.new(body["lines"], &{&1["account_number"], &1})
      assert lines["411"]["direction"] == "debit"
      assert lines["411"]["amount"] == "1200.00"
      assert lines["702"]["direction"] == "credit"
      assert lines["702"]["amount"] == "1000.00"
      assert lines["4532"]["direction"] == "credit"
      assert lines["4532"]["amount"] == "200.00"

      shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
      assert shown["status"] == "posted"
      assert shown["journal_entry_id"] == body["id"]

      conn = post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      assert json_response(conn, 409)["detail"] == "фактурата е вече постната"

      conn = patch(conn, "/v1/invoices/#{inv["id"]}", %{"notes" => "x"})

      assert json_response(conn, 409)["detail"] ==
               "фактурата е осчетоводена — първо я върни към чернова"
    end

    test "покупка: Дт 302 / Дт 4531 / Кт 401", %{conn: conn, cp_id: cp_id, goods_id: goods_id} do
      line = %{
        "product_id" => goods_id,
        "description" => "Материал",
        "quantity" => "5",
        "unit_price" => "50.00",
        "vat_rate" => "20",
        "net_amount" => "250.00",
        "vat_amount" => "50.00",
        "total_amount" => "300.00"
      }

      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "in",
            "number" => "IN-9",
            "issue_date" => "2026-11-02",
            "counterpart_id" => cp_id,
            "lines" => [line]
          }),
          201
        )

      body = json_response(post(conn, "/v1/invoices/#{inv["id"]}/post", %{}), 201)
      assert body["vat_type"] == "purchase"

      lines = Map.new(body["lines"], &{&1["account_number"], &1})
      assert lines["302"]["direction"] == "debit"
      assert lines["302"]["amount"] == "250.00"
      assert lines["4531"]["direction"] == "debit"
      assert lines["4531"]["amount"] == "50.00"
      assert lines["401"]["direction"] == "credit"
      assert lines["401"]["amount"] == "300.00"
    end

    test "проформа не се осчетоводява", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "document_type" => "proforma",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      conn = post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

      assert json_response(conn, 422)["detail"] ==
               "проформата не е данъчен документ и не се осчетоводява"
    end

    test "затворен месец спира поста", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      post(conn, "/v1/accounting-periods/close", %{"year" => 2026, "month" => 11})

      conn = post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      assert json_response(conn, 422)["detail"] == "периодът 2026-11 е затворен"
    end

    test "отпост връща чернова и трие дневника", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      entry = json_response(post(conn, "/v1/invoices/#{inv["id"]}/post", %{}), 201)

      conn = post(conn, "/v1/invoices/bulk/unpost", %{"ids" => [inv["id"]]})
      assert json_response(conn, 200)["unposted"] == 1

      shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
      assert shown["status"] == "draft"

      conn = get(conn, "/v1/journal/#{entry["id"]}")
      assert json_response(conn, 404)["detail"] == "записът не е намерен"
    end

    test "групова пост и триене", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      body = %{
        "direction" => "out",
        "issue_date" => "2026-11-01",
        "counterpart_id" => cp_id,
        "lines" => [sale_line(service_id)]
      }

      first = json_response(post(conn, "/v1/invoices", body), 201)
      second = json_response(post(conn, "/v1/invoices", body), 201)

      conn = post(conn, "/v1/invoices/bulk/post", %{"ids" => [first["id"], second["id"]]})
      result = json_response(conn, 200)
      assert result["posted"] == 2
      assert result["failed"] == 0

      conn = post(conn, "/v1/invoices/bulk/delete", %{"ids" => [first["id"], second["id"]]})
      assert json_response(conn, 200)["deleted"] == 2
    end
  end

  describe "ръчен запис в дневника" do
    test "балансиран запис и небалансиран отказ", %{conn: conn, by_number: by_number} do
      lines = [
        %{"account_id" => by_number["501"], "direction" => "debit", "amount" => "100.00"},
        %{"account_id" => by_number["702"], "direction" => "credit", "amount" => "100.00"}
      ]

      conn =
        post(conn, "/v1/journal", %{
          "entry_date" => "2026-11-05",
          "description" => "Ръчен",
          "lines" => lines
        })

      body = json_response(conn, 201)
      assert body["document_type"] == "manual"
      assert body["document_number"] == "MANUAL-#{body["id"]}"
      assert length(body["lines"]) == 2

      conn =
        post(conn, "/v1/journal", %{
          "entry_date" => "2026-11-05",
          "lines" => [
            %{"account_id" => by_number["501"], "direction" => "debit", "amount" => "100.00"}
          ]
        })

      assert json_response(conn, 422)["detail"] =~ "записът не е балансиран"

      conn = delete(conn, "/v1/journal/#{body["id"]}")
      assert response(conn, 204)
    end

    test "фактурен запис не се редактира ръчно", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [sale_line(service_id)]
          }),
          201
        )

      entry = json_response(post(conn, "/v1/invoices/#{inv["id"]}/post", %{}), 201)

      conn =
        put(conn, "/v1/journal/#{entry["id"]}", %{"entry_date" => "2026-11-06", "lines" => []})

      assert json_response(conn, 403)["detail"] == "само ръчни записи могат да се редактират"
    end
  end

  describe "периоди" do
    test "дванадесет месеца, затваряне и отваряне", %{conn: conn} do
      body = json_response(get(conn, "/v1/accounting-periods?year=2026"), 200)
      assert body["year"] == 2026
      assert length(body["items"]) == 12
      assert Enum.all?(body["items"], &(&1["status"] == "open"))

      conn =
        post(conn, "/v1/accounting-periods/close", %{
          "year" => 2026,
          "month" => 3,
          "notes" => "Приключен"
        })

      body = json_response(conn, 200)
      march = Enum.find(body["items"], &(&1["month"] == 3))
      assert march["status"] == "closed"
      assert march["notes"] == "Приключен"

      conn = post(conn, "/v1/accounting-periods/reopen", %{"year" => 2026, "month" => 3})
      body = json_response(conn, 200)
      assert Enum.find(body["items"], &(&1["month"] == 3))["status"] == "open"

      conn = post(conn, "/v1/accounting-periods/close", %{"year" => 2026, "month" => 13})
      assert json_response(conn, 422)["detail"] == "month трябва да е 1–12"
    end
  end
end

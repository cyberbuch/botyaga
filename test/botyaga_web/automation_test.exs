defmodule BotyagaWeb.AutomationTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("auto@baga.example", "Автоматизация", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Авто ООД", "eik" => "207123457"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)

    post(conn, "/v1/companies/#{company.id}/document-series", %{
      "name" => "Фактури",
      "document_types" => ~w(01 02 03)
    })

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент Демо", "eik" => "111222334"}),
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

  defp sale_line(service_id) do
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
    }
  end

  defp purchase_line(goods_id) do
    %{
      "product_id" => goods_id,
      "description" => "Материал",
      "quantity" => "5",
      "unit" => "KGM",
      "unit_price" => "20.00",
      "vat_rate" => "20",
      "net_amount" => "100.00",
      "vat_amount" => "20.00",
      "total_amount" => "120.00"
    }
  end

  defp set_defaults(conn, company_id, map) do
    patch(conn, "/v1/companies/#{company_id}", %{
      "settings" => Jason.encode!(%{"default_accounts" => map})
    })
  end

  defp make_invoice(conn, cp_id, line, attrs) do
    json_response(
      post(
        conn,
        "/v1/invoices",
        Map.merge(
          %{
            "direction" => "out",
            "issue_date" => "2026-11-01",
            "counterpart_id" => cp_id,
            "lines" => [line]
          },
          attrs
        )
      ),
      201
    )
  end

  defp journal_lines(conn, entry_id) do
    body = json_response(get(conn, "/v1/journal/#{entry_id}"), 200)
    Map.new(body["lines"], &{&1["account_number"], &1})
  end

  describe "default сметки в поста" do
    test "клиент и ДДС идват от настройките", %{
      conn: conn,
      company: company,
      cp_id: cp_id,
      service_id: service_id
    } do
      post(conn, "/v1/accounts", %{"number" => "4111", "name" => "Клиенти подробен"})
      post(conn, "/v1/accounts", %{"number" => "45321", "name" => "ДДС продажби подробен"})
      set_defaults(conn, company.id, %{"customers" => "4111", "vat_sale" => "45321"})

      inv = make_invoice(conn, cp_id, sale_line(service_id), %{})
      body = json_response(post(conn, "/v1/invoices/#{inv["id"]}/post", %{}), 201)
      lines = Map.new(body["lines"], &{&1["account_number"], &1})

      assert lines["4111"]["direction"] == "debit"
      assert lines["45321"]["direction"] == "credit"
      refute Map.has_key?(lines, "411")
      refute Map.has_key?(lines, "4532")
    end

    test "без настройки ползва стандартните номера", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{})
      body = json_response(post(conn, "/v1/invoices/#{inv["id"]}/post", %{}), 201)
      lines = Map.new(body["lines"], &{&1["account_number"], &1})

      assert lines["411"]["direction"] == "debit"
      assert lines["4532"]["direction"] == "credit"
    end
  end

  describe "плащания" do
    test "в брой: Дт каса / Кт клиенти", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "в брой"})
      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

      pay = json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 201)
      assert pay["amount"] == "1200.00"

      lines = journal_lines(conn, pay["id"])
      assert lines["501"]["direction"] == "debit"
      assert lines["501"]["amount"] == "1200.00"
      assert lines["411"]["direction"] == "credit"

      shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
      assert shown["is_paid"] == true
      assert shown["payment_entry_id"] == pay["id"]
    end

    test "карта на покупка: Дт доставчици / Кт буфер", %{
      conn: conn,
      company: company,
      cp_id: cp_id,
      goods_id: goods_id
    } do
      post(conn, "/v1/accounts", %{"number" => "505", "name" => "Разчети по карти"})
      set_defaults(conn, company.id, %{"card_purchase" => "505"})

      inv =
        make_invoice(conn, cp_id, purchase_line(goods_id), %{
          "direction" => "in",
          "number" => "IN-9",
          "payment_method" => "карта"
        })

      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      pay = json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 201)

      lines = journal_lines(conn, pay["id"])
      assert lines["401"]["direction"] == "debit"
      assert lines["505"]["direction"] == "credit"
      assert lines["505"]["amount"] == "120.00"
    end

    test "банков превод: Дт банка / Кт клиенти", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv =
        make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "банков превод"})

      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      pay = json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 201)

      lines = journal_lines(conn, pay["id"])
      assert lines["503"]["direction"] == "debit"
      assert lines["411"]["direction"] == "credit"
    end

    test "unpay трие статията", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "в брой"})
      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      pay = json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 201)

      assert response(post(conn, "/v1/invoices/#{inv["id"]}/unpay", %{}), 204)
      assert response(get(conn, "/v1/journal/#{pay["id"]}"), 404)

      shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
      assert shown["is_paid"] == false
    end

    test "отпост трие и плащането", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "в брой"})
      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      pay = json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 201)

      post(conn, "/v1/invoices/bulk/unpost", %{"ids" => [inv["id"]]})
      assert response(get(conn, "/v1/journal/#{pay["id"]}"), 404)
    end

    test "само осчетоводена фактура се плаща", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "в брой"})

      assert json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 422)["detail"] ==
               "плаща се само осчетоводена фактура"
    end

    test "повторно плащане се отказва", %{conn: conn, cp_id: cp_id, service_id: service_id} do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "в брой"})
      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
      post(conn, "/v1/invoices/#{inv["id"]}/pay", %{})

      assert json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 409)["detail"] ==
               "фактурата вече е платена"
    end

    test "компенсация не се плаща автоматично", %{
      conn: conn,
      cp_id: cp_id,
      service_id: service_id
    } do
      inv = make_invoice(conn, cp_id, sale_line(service_id), %{"payment_method" => "компенсация"})
      post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

      assert json_response(post(conn, "/v1/invoices/#{inv["id"]}/pay", %{}), 422)["detail"] =~
               "не се плаща автоматично"
    end
  end
end

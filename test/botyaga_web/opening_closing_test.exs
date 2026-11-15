defmodule BotyagaWeb.OpeningClosingTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("oc@baga.example", "Салда", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Салда ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})
    {:ok, conn: conn, company: company, by_number: by_number}
  end

  describe "начални салда" do
    test "създаване, страна по НСС и сборове", %{conn: conn, by_number: by_number} do
      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "1000.00"
        })

      body = json_response(conn, 201)
      assert body["status"] == "created"
      assert body["natural_side"] == "debit"
      assert body["account_kind"] == "cash"

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "credit" => "50.00"
        })

      assert json_response(conn, 422)["detail"] ==
               "501 е дебитна по НСС — началното салдо е в дебит"

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["101"],
          "credit" => "1000.00"
        })

      assert json_response(conn, 201)["natural_side"] == "credit"

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "10.00",
          "credit" => "10.00"
        })

      assert json_response(conn, 422)["detail"] == "салдото е или дебит, или кредит — не и двете"

      body = json_response(get(conn, "/v1/opening-balances?year=2026"), 200)
      assert body["count"] == 2
      assert body["total_debit"] == "1000.00"
      assert body["total_credit"] == "1000.00"
      assert body["difference"] == "0.00"
    end

    test "аналитична сметка иска контрагент", %{conn: conn} do
      account =
        json_response(
          post(conn, "/v1/accounts", %{
            "number" => "41101",
            "name" => "Клиенти аналитично",
            "analytic_type" => "counterpart"
          }),
          201
        )

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => account["id"],
          "debit" => "100.00"
        })

      assert json_response(conn, 422)["detail"] == "41101 е аналитична към контрагент"
    end

    test "затворен януари спира записа", %{conn: conn, by_number: by_number} do
      post(conn, "/v1/accounting-periods/close", %{"year" => 2026, "month" => 1})

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "100.00"
        })

      assert json_response(conn, 422)["detail"] == "периодът 2026-01 е затворен"
    end

    test "редакция и триене", %{conn: conn, by_number: by_number} do
      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "100.00"
        })

      assert response(conn, 201)

      row = hd(json_response(get(conn, "/v1/opening-balances?year=2026"), 200)["items"])

      conn =
        patch(conn, "/v1/opening-balances/#{row["id"]}", %{
          "debit" => "200.00",
          "description" => "Каса"
        })

      body = json_response(conn, 200)
      assert body["debit"] == "200.00"
      assert body["description"] == "Каса"

      conn = delete(conn, "/v1/opening-balances/#{row["id"]}")
      assert response(conn, 204)
    end
  end

  describe "приключвателни операции" do
    setup %{conn: conn, company: company, by_number: by_number} do
      settings =
        ~s({"closing_map":[{"source":"602","target":"612"},{"source":"60","target":"611"}]})

      patch(conn, "/v1/companies/#{company.id}", %{"settings" => settings})

      lines = [
        %{"account_id" => by_number["60101"], "direction" => "debit", "amount" => "100.00"},
        %{"account_id" => by_number["60201"], "direction" => "debit", "amount" => "25.50"},
        %{"account_id" => by_number["401"], "direction" => "credit", "amount" => "125.50"}
      ]

      entry =
        json_response(
          post(conn, "/v1/journal", %{
            "entry_date" => "2026-05-10",
            "description" => "Разходи",
            "lines" => lines
          }),
          201
        )

      {:ok, entry: entry}
    end

    test "преглед и запис на балансирана статия", %{conn: conn} do
      conn = get(conn, "/v1/closing-operations/preview?year=2026&month=5")
      body = json_response(conn, 200)
      assert body["count"] == 2
      assert body["total"] == "125.50"
      assert body["entry_date"] == "2026-05-31"
      assert body["document_number"] == "CLOSE-2026-05"
      assert body["already_done"] == false
      assert Enum.map(body["lines"], & &1["source_number"]) == ["60101", "60201"]

      conn = post(conn, "/v1/closing-operations/run", %{"year" => 2026, "month" => 5})
      body = json_response(conn, 200)
      assert body["entry_id"] > 0

      entry = json_response(get(conn, "/v1/journal/#{body["entry_id"]}"), 200)
      assert entry["document_type"] == "closing"

      debit =
        entry["lines"] |> Enum.filter(&(&1["direction"] == "debit")) |> Enum.map(& &1["amount"])

      credit =
        entry["lines"] |> Enum.filter(&(&1["direction"] == "credit")) |> Enum.map(& &1["amount"])

      assert Enum.sum(Enum.map(debit, &String.to_float/1)) ==
               Enum.sum(Enum.map(credit, &String.to_float/1))

      conn = post(conn, "/v1/closing-operations/run", %{"year" => 2026, "month" => 5})
      assert json_response(conn, 409)["detail"] =~ "вече е записано"
    end

    test "без салда и невалиден месец", %{conn: conn} do
      # месец преди разхода няма салда за приключване
      conn = post(conn, "/v1/closing-operations/run", %{"year" => 2026, "month" => 4})
      assert json_response(conn, 422)["detail"] =~ "няма салда за приключване"

      conn = get(conn, "/v1/closing-operations/preview?year=2026&month=13")
      assert json_response(conn, 422)["detail"] == "month трябва да е 1–12"
    end
  end

  describe "специални документи" do
    setup %{conn: conn, by_number: by_number} do
      cp =
        json_response(
          post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
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

      line = %{
        "product_id" => product["id"],
        "description" => "Внос",
        "quantity" => "1",
        "unit_price" => "1000.00",
        "vat_rate" => "0",
        "net_amount" => "1000.00",
        "vat_amount" => "0.00",
        "total_amount" => "1000.00"
      }

      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "in",
            "number" => "IN-100",
            "issue_date" => "2026-06-01",
            "counterpart_id" => cp["id"],
            "lines" => [line]
          }),
          201
        )

      {:ok, inv: inv}
    end

    test "протокол по чл. 117 начислява ДДС", %{conn: conn, inv: inv} do
      conn = post(conn, "/v1/invoices/#{inv["id"]}/issue-protocol", %{})
      body = json_response(conn, 201)
      assert body["document_type"] == "09"
      assert body["direction"] == "in"
      assert body["vat_article"] == "чл. 117"
      assert body["vat_amount"] == "200.00"
      assert body["total_amount"] == "1200.00"
      assert body["original_invoice_id"] == inv["id"]

      entry = json_response(post(conn, "/v1/invoices/#{body["id"]}/post", %{}), 201)
      assert entry["vat_type"] == "both"
      lines = Map.new(entry["lines"], &{&1["account_number"], &1})
      assert lines["4531"]["direction"] == "debit"
      assert lines["4532"]["direction"] == "credit"
    end

    test "митническа декларация иска MRN", %{conn: conn, inv: inv} do
      conn = post(conn, "/v1/invoices/#{inv["id"]}/issue-customs", %{})

      assert json_response(conn, 422)["detail"] ==
               "номерът на митническата декларация (MRN) е задължителен"

      conn =
        post(conn, "/v1/invoices/#{inv["id"]}/issue-customs", %{
          "number" => "MRN-1",
          "customs_duty" => "50.00"
        })

      body = json_response(conn, 201)
      assert body["document_type"] == "07"
      assert body["customs_statistical"] == "1000.00"
      assert body["customs_duty"] == "50.00"
      assert body["customs_vat"] == "210.00"
      assert body["total_amount"] == "1260.00"
    end

    test "протокол само към входяща фактура", %{conn: conn, by_number: by_number} do
      cp =
        json_response(
          post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "222333444"}),
          201
        )

      product =
        json_response(
          post(conn, "/v1/products", %{
            "name" => "Услуга",
            "is_service" => true,
            "revenue_account_id" => by_number["702"]
          }),
          201
        )

      out =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-06-01",
            "counterpart_id" => cp["id"],
            "lines" => [
              %{
                "product_id" => product["id"],
                "description" => "x",
                "quantity" => "1",
                "unit_price" => "100.00",
                "vat_rate" => "20",
                "net_amount" => "100.00",
                "vat_amount" => "20.00",
                "total_amount" => "120.00"
              }
            ]
          }),
          201
        )

      conn = post(conn, "/v1/invoices/#{out["id"]}/issue-protocol", %{})

      assert json_response(conn, 422)["detail"] ==
               "протокол по чл. 117 се издава само към входяща фактура"
    end
  end
end

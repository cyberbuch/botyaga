defmodule BotyagaWeb.PrintingTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("print@baga.example", "Печат", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(
        %{"name" => "Печат ООД", "eik" => "207123456", "mol" => "Иван Петров"},
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

    goods =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => "S-1",
          "issue_date" => "2026-01-15",
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => goods["id"],
              "description" => "Продажба",
              "quantity" => "2",
              "unit_price" => "100.00",
              "vat_rate" => "20",
              "net_amount" => "200.00",
              "vat_amount" => "40.00",
              "total_amount" => "240.00"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

    {:ok, conn: conn, company: company, by_number: by_number, cp: cp, goods: goods, inv: inv}
  end

  describe "печат на фактура" do
    test "docx и odt са архиви", %{conn: conn, inv: inv} do
      conn = get(conn, "/v1/invoices/#{inv["id"]}/print?format=docx")
      assert response(conn, 200)

      assert get_resp_header(conn, "content-type") == [
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
             ]

      docx = response(conn, 200)
      assert binary_part(docx, 0, 2) == "PK"
      assert docx =~ "word/document"
      assert docx =~ "ФАКТУРА"

      conn = get(conn, "/v1/invoices/#{inv["id"]}/print?format=odt")
      odt = response(conn, 200)
      assert binary_part(odt, 0, 2) == "PK"
      assert odt =~ "mimetype"
    end

    test "pdf без sidecar връща 503", %{conn: conn, inv: inv} do
      conn = get(conn, "/v1/invoices/#{inv["id"]}/print?format=pdf")
      assert json_response(conn, 503)["detail"] =~ "sidecar"
    end

    test "невалиден формат", %{conn: conn, inv: inv} do
      conn = get(conn, "/v1/invoices/#{inv["id"]}/print?format=bogus")
      assert json_response(conn, 422)["detail"] == "format трябва да е pdf/docx/odt"
    end

    test "банкова сметка и подписи в печата", %{
      conn: conn,
      company: company,
      cp: cp,
      goods: goods,
      by_number: by_number
    } do
      patch(conn, "/v1/counterparts/#{cp["id"]}", %{"contact_person" => "Мария Контакт"})

      ba =
        json_response(
          post(conn, "/v1/bank-accounts", %{
            "iban" => "BG80BNPA94405031",
            "name" => "ОББ",
            "bic" => "UBBSBGSF",
            "gl_account_id" => by_number["503"]
          }),
          201
        )

      inv =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "issue_date" => "2026-01-15",
            "counterpart_id" => cp["id"],
            "payment_method" => "банков превод",
            "bank_account_id" => ba["id"],
            "lines" => [
              %{
                "product_id" => goods["id"],
                "description" => "Продажба",
                "quantity" => "2",
                "unit_price" => "100.00",
                "vat_rate" => "20",
                "net_amount" => "200.00",
                "vat_amount" => "40.00",
                "total_amount" => "240.00"
              }
            ]
          }),
          201
        )

      {:ok, doc} = Botyaga.Printing.Load.load(company.id, inv["id"])
      blocks = Botyaga.Printing.Invoice.blocks(doc, false)

      lines = for {:line, t} <- blocks, do: t
      assert Enum.any?(lines, &(&1 =~ "По банкова сметка"))
      assert Enum.any?(lines, &(&1 =~ "Банка: ОББ"))
      assert Enum.any?(lines, &(&1 =~ "IBAN: BG80BNPA94405031"))
      assert Enum.any?(lines, &(&1 =~ "BIC: UBBSBGSF"))

      tables = for {:table, rows} <- blocks, do: rows
      flat = List.flatten(tables)
      assert Enum.any?(flat, &(&1 =~ "Съставил: Иван Петров"))
      assert Enum.any?(flat, &(&1 =~ "Получил: Мария Контакт"))
      assert Enum.any?(tables, fn rows -> Enum.member?(hd(rows), "ДДС%") end)
    end
  end

  describe "експорт на справки" do
    test "xlsx и ods", %{conn: conn} do
      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&from=2026-01-01&to=2026-12-31&format=xlsx&bg=1"
        )

      assert response(conn, 200)
      xlsx = response(conn, 200)
      assert binary_part(xlsx, 0, 2) == "PK"

      assert get_resp_header(conn, "content-disposition") == [
               "attachment; filename=\"oborotna-2026-01-01-2026-12-31.xlsx\""
             ]

      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&from=2026-01-01&to=2026-12-31&format=ods"
        )

      ods = response(conn, 200)
      assert binary_part(ods, 0, 2) == "PK"
      assert ods =~ "mimetype"
    end

    test "pdf без sidecar и невалиден формат", %{conn: conn} do
      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&from=2026-01-01&to=2026-12-31&format=pdf"
        )

      assert json_response(conn, 503)["detail"] =~ "sidecar"

      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&from=2026-01-01&to=2026-12-31&format=bogus"
        )

      assert json_response(conn, 400)["detail"] == "format трябва да е pdf, xlsx или ods"
    end
  end

  describe "печат на протокол" do
    test "docx на вътрешен протокол", %{conn: conn, company: company, cp: cp, goods: goods} do
      loc1 =
        json_response(
          post(conn, "/v1/companies/#{company.id}/locations", %{
            "name" => "Склад 1",
            "location_type" => "WAREHOUSE"
          }),
          201
        )

      loc2 =
        json_response(
          post(conn, "/v1/companies/#{company.id}/locations", %{
            "name" => "Склад 2",
            "location_type" => "WAREHOUSE"
          }),
          201
        )

      buy =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "in",
            "number" => "P-1",
            "issue_date" => "2026-01-01",
            "counterpart_id" => cp["id"],
            "location_id" => loc1["id"],
            "lines" => [
              %{
                "product_id" => goods["id"],
                "description" => "Покупка",
                "quantity" => "20",
                "unit_price" => "10.00",
                "vat_rate" => "20",
                "net_amount" => "200.00",
                "vat_amount" => "40.00",
                "total_amount" => "240.00"
              }
            ]
          }),
          201
        )

      post(conn, "/v1/invoices/#{buy["id"]}/post", %{})

      doc =
        json_response(
          post(conn, "/v1/internal-docs", %{
            "doc_date" => "2026-01-15",
            "from_location_id" => loc1["id"],
            "to_location_id" => loc2["id"],
            "lines" => [
              %{"line_kind" => "product", "product_id" => goods["id"], "quantity" => "5"}
            ]
          }),
          201
        )

      post(conn, "/v1/internal-docs/#{doc["id"]}/confirm", %{})

      conn = get(conn, "/v1/internal-docs/#{doc["id"]}/print?format=docx")
      assert response(conn, 200)
      docx = response(conn, 200)
      assert binary_part(docx, 0, 2) == "PK"
      assert docx =~ "ПРИЕМО-ПРЕДАВАТЕЛЕН ПРОТОКОЛ"
    end
  end
end

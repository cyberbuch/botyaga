defmodule BotyagaWeb.SaftTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("saft@baga.example", "САФТ", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(
        %{
          "name" => "САФТ ООД",
          "eik" => "207123456",
          "region" => "София",
          "city" => "София",
          "mol" => "Иван Петров",
          "iban" => "BG12BANK1234567890"
        },
        user
      )

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{
          "name" => "Клиент АД",
          "eik" => "111222333",
          "counterpart_type" => "customer"
        }),
        201
      )

    goods =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"],
          "expense_account_id" => by_number["60101"]
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

    {:ok, conn: conn, company: company, by_number: by_number, cp: cp, goods: goods}
  end

  defp export(conn, query) do
    conn = get(conn, "/v1/saft/export?#{query}")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    xml = response(conn, 200)
    assert well_formed?(xml)
    xml
  end

  defp well_formed?(xml) do
    path = Path.join(System.tmp_dir!(), "saft_#{:erlang.unique_integer([:positive])}.xml")
    File.write!(path, xml)

    try do
      {_doc, _rest} = :xmerl_scan.file(String.to_charlist(path), quiet: true)
      true
    after
      File.rm(path)
    end
  end

  describe "експорт" do
    test "месечен файл", %{conn: conn} do
      xml = export(conn, "period=2026-01-01&mode=monthly")
      assert xml =~ "<nsSAFT:AuditFile"
      assert xml =~ "GeneralLedgerAccounts"
      assert xml =~ "SalesInvoices"
      assert xml =~ "САФТ ООД"
      assert xml =~ "AuditFileRegion"
      assert xml =~ "BG-22"
      assert xml =~ "S-1"
    end

    test "годишен файл", %{conn: conn} do
      xml = export(conn, "period=2026-01-01&mode=annual")
      assert xml =~ "MasterFilesAnnual"
      assert xml =~ "SourceDocumentsAnnual"
    end

    test "при поискване", %{conn: conn} do
      xml = export(conn, "period=2026-01-01&mode=ondemand")
      assert xml =~ "MasterFilesOnDemand"
      assert xml =~ "PhysicalStock"
      assert xml =~ "MovementOfGoods"
    end

    test "при поискване с дати от-до", %{conn: conn} do
      xml =
        export(conn, "period=2026-01-01&mode=ondemand&date_from=2026-01-01&date_to=2026-03-31")

      assert xml =~ "PhysicalStock"
      assert xml =~ "PeriodStartYear"
    end

    test "грешни дати и период", %{conn: conn} do
      conn =
        get(
          conn,
          "/v1/saft/export?period=2026-01-01&mode=ondemand&date_from=2026-03-01&date_to=2026-01-01"
        )

      assert json_response(conn, 400)["detail"] ==
               "date_from трябва да е преди или равен на date_to"

      conn = get(conn, "/v1/saft/export?period=2026-01-02")
      assert json_response(conn, 400)["detail"] == "period е задължителен (YYYY-MM-01)"

      conn = get(conn, "/v1/saft/export")
      assert json_response(conn, 400)["detail"] == "period е задължителен (YYYY-MM-01)"
    end
  end

  describe "кореспонденции (movement mappings)" do
    test "видове и стандартни", %{conn: conn} do
      body = json_response(get(conn, "/v1/saft/movement-mappings?kind=stock"), 200)
      assert body["count"] == 0
      assert Enum.any?(body["types"], &(&1["code"] == "10"))

      conn = get(conn, "/v1/saft/movement-mappings?kind=bogus")
      assert json_response(conn, 400)["detail"] =~ "непознат вид кореспонденция"

      defaults =
        json_response(
          post(conn, "/v1/saft/movement-mappings/defaults", %{"kind" => "stock"}),
          200
        )

      assert defaults["count"] > 0

      conn = post(conn, "/v1/saft/movement-mappings/defaults", %{"kind" => "stock"})
      assert json_response(conn, 422)["detail"] =~ "вече има кореспонденции"
    end

    test "създаване, редакция и триене", %{conn: conn} do
      row =
        json_response(
          post(conn, "/v1/saft/movement-mappings", %{
            "kind" => "cash",
            "type_code" => "10",
            "debit_account" => "501",
            "credit_account" => "411",
            "description" => "Каса"
          }),
          201
        )

      assert row["type_name"] == "Плащане в брой - приход"
      assert row["is_active"] == 1

      conn =
        post(conn, "/v1/saft/movement-mappings", %{
          "kind" => "cash",
          "type_code" => "999",
          "debit_account" => "501",
          "credit_account" => "411"
        })

      assert json_response(conn, 422)["detail"] == "непознат тип движение за този вид"

      conn =
        post(conn, "/v1/saft/movement-mappings", %{
          "kind" => "cash",
          "type_code" => "10",
          "credit_account" => "411"
        })

      assert json_response(conn, 422)["detail"] == "debit_account е задължително"

      updated =
        json_response(
          patch(conn, "/v1/saft/movement-mappings/#{row["id"]}", %{"debit_account" => "503"}),
          200
        )

      assert updated["debit_account"] == "503"

      conn = patch(conn, "/v1/saft/movement-mappings/#{row["id"]}", %{"debit_account" => ""})
      assert json_response(conn, 422)["detail"] == "дебит и кредит сметките са задължителни"

      conn = delete(conn, "/v1/saft/movement-mappings/#{row["id"]}")
      assert response(conn, 204)

      conn = delete(conn, "/v1/saft/movement-mappings/#{row["id"]}")
      assert json_response(conn, 404)["detail"] == "кореспонденцията не е намерена"
    end
  end
end

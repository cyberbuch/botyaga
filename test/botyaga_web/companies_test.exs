defmodule BotyagaWeb.CompaniesTest do
  use BotyagaWeb.ConnCase, async: false

  import Ecto.Query

  alias Botyaga.{Access, Accounts, Companies, Repo}
  alias Botyaga.Invoicing.Invoice

  describe "фирми и права" do
    test "супер администратор създава фирма и сее сметкоплана" do
      super = superadmin()

      conn =
        build_conn()
        |> auth_conn(super)
        |> post("/v1/companies", %{"name" => "Тест ООД", "eik" => "207123456"})

      body = json_response(conn, 201)
      assert body["name"] == "Тест ООД"
      assert body["saft_accounts_seeded"] == 360
      assert body["currency"] == "EUR"
      assert body["vat_period"] == "monthly"
      assert body["inventory_valuation_method"] == "WAC"

      company = Companies.get_company(body["id"])

      assert Repo.aggregate(
               from(a in Botyaga.Catalog.Account, where: a.company_id == ^company.id),
               :count,
               :id
             ) == 360
    end

    test "обикновен потребител не може да създава фирми" do
      super = superadmin()

      {:ok, company, _seeded} =
        Companies.create(%{"name" => "Моята", "eik" => "777888999"}, super)

      {:ok, user} = Accounts.create_user("фуз@baga.example", "Фуз", "парола-123")
      {:ok, role_id} = Access.role_id_by_name(Access.role_admin())
      Access.grant(user.id, company.id, role_id)
      Companies.set_active(user.username, company.id)

      conn =
        build_conn()
        |> auth_conn(user)
        |> post("/v1/companies", %{"name" => "Непозволена", "eik" => "111111111"})

      assert json_response(conn, 403)["detail"] == "създаването на фирма е за супер администратор"
    end

    test "дубликат по ЕИК е 409" do
      super = superadmin()

      conn =
        build_conn()
        |> auth_conn(super)
        |> post("/v1/companies", %{"name" => "Първа", "eik" => "333444555"})

      assert response(conn, 201)

      conn =
        build_conn()
        |> auth_conn(super)
        |> post("/v1/companies", %{"name" => "Втора", "eik" => "333444555"})

      assert json_response(conn, 409)["detail"] == "фирма с този ЕИК вече съществува"
    end

    test "чужда фирма е 404 за обикновен потребител" do
      super = superadmin()
      {:ok, own, _seeded} = Companies.create(%{"name" => "Моята", "eik" => "777888999"}, super)

      {:ok, foreign, _seeded} =
        Companies.create(%{"name" => "Чуждата", "eik" => "777888998"}, super)

      {:ok, other} = Accounts.create_user("друг@baga.example", "Друг", "парола-123")
      {:ok, role_id} = Access.role_id_by_name(Access.role_admin())
      Access.grant(other.id, own.id, role_id)
      Companies.set_active(other.username, own.id)

      conn =
        build_conn()
        |> auth_conn(other)
        |> get("/v1/companies/#{foreign.id}")

      assert json_response(conn, 404)["detail"] == "фирмата не е намерена"
    end

    test "списъкът с фирми е само с достъпните" do
      super = superadmin()
      {:ok, mine, _seeded} = Companies.create(%{"name" => "Моята", "eik" => "777888999"}, super)
      {:ok, user} = Accounts.create_user("член@baga.example", "Член", "парола-123")
      {:ok, role_id} = Access.role_id_by_name(Access.role_admin())
      Access.grant(user.id, mine.id, role_id)
      Companies.set_active(user.username, mine.id)

      conn = build_conn() |> auth_conn(user) |> get("/v1/companies")
      body = json_response(conn, 200)
      assert [company] = body["items"]
      assert company["name"] == "Моята"
      assert body["count"] == 1
    end
  end

  describe "настройки на фирма" do
    test "обекти, серии и следващ номер" do
      super = superadmin()
      {:ok, company, _seeded} = Companies.create(%{"name" => "Тест", "eik" => "207123456"}, super)
      Companies.set_active(super.username, company.id)

      conn =
        build_conn()
        |> auth_conn(super)
        |> post("/v1/companies/#{company.id}/locations", %{
          "name" => "Офис Витоша",
          "location_type" => "OFFICE"
        })

      assert json_response(conn, 201)["name"] == "Офис Витоша"

      conn =
        build_conn()
        |> auth_conn(super)
        |> post("/v1/companies/#{company.id}/document-series", %{
          "name" => "Фактури",
          "document_types" => ~w(01 02 03),
          "pad_width" => 10,
          "start_number" => 1
        })

      series = json_response(conn, 201)
      assert series["next_number"] == "0000000001"

      Repo.insert!(%Invoice{
        company_id: company.id,
        direction: "out",
        document_type: "01",
        number: "0000000001",
        issue_date: "2026-11-01",
        status: "posted",
        net_amount: "1000.00",
        vat_amount: "200.00",
        total_amount: "1200.00"
      })

      conn =
        build_conn()
        |> auth_conn(super)
        |> patch("/v1/document-series/#{series["id"]}", %{
          "name" => "Фактури",
          "document_types" => ~w(01 02 03)
        })

      assert json_response(conn, 200)["next_number"] == "0000000002"
    end

    test "settings връща фирмата и списъците" do
      super = superadmin()
      {:ok, company, _seeded} = Companies.create(%{"name" => "Тест", "eik" => "207123456"}, super)
      Companies.set_active(super.username, company.id)

      conn = build_conn() |> auth_conn(super) |> get("/v1/companies/#{company.id}/settings")
      body = json_response(conn, 200)
      assert body["company"]["name"] == "Тест"
      assert body["locations"] == []
      assert body["document_series"] == []
    end
  end

  describe "табло" do
    test "суми от фактурите по посока" do
      super = superadmin()
      {:ok, company, _seeded} = Companies.create(%{"name" => "Тест", "eik" => "207123456"}, super)
      Companies.set_active(super.username, company.id)

      Repo.insert!(%Invoice{
        company_id: company.id,
        direction: "out",
        document_type: "01",
        number: "0000000001",
        issue_date: "2026-11-01",
        status: "posted",
        net_amount: "1000.00",
        vat_amount: "200.00",
        total_amount: "1200.00"
      })

      Repo.insert!(%Invoice{
        company_id: company.id,
        direction: "in",
        document_type: "02",
        number: "0000000042",
        issue_date: "2026-11-02",
        status: "draft",
        net_amount: "250.00",
        vat_amount: "50.00",
        total_amount: "300.00"
      })

      conn = build_conn() |> auth_conn(super) |> get("/v1/dashboard")
      body = json_response(conn, 200)

      assert body["invoices_draft"] == 1
      assert body["invoices_posted"] == 1
      assert body["receivables"] == "1200.00"
      assert body["payables"] == "300.00"
      assert body["vat_output"] == "200.00"
      assert body["vat_input"] == "50.00"
      assert body["revenue_ytd"] == "1000.00"
      assert body["expense_ytd"] == "250.00"
      assert body["bank_total"] == "0.00"
      assert length(body["recent"]) == 2
      assert hd(body["recent"])["number"] == "0000000042"
    end

    test "без активна фирма таблото е празно" do
      {:ok, user} = Accounts.create_user("празен@baga.example", "Празен", "парола-123")

      conn = build_conn() |> auth_conn(user) |> get("/v1/dashboard")
      body = json_response(conn, 200)
      assert body["company_id"] == 0
      assert body["receivables"] == "0.00"
    end
  end

  defp superadmin do
    {:ok, user} =
      Accounts.create_user("root@baga.example", "Супер", "парола-123", "super_admin",
        is_super_admin: 1
      )

    user
  end
end

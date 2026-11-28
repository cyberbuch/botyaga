defmodule BotyagaWeb.AuditFixesTest do
  @moduledoc """
  Регресионни тестове за одита: IDOR валидации (чужди референции към фирма),
  валидация на начални салда, content-disposition, изтриване на потребител/фирма.
  """

  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Access, Accounts, Companies, Repo}
  alias Botyaga.Access.Membership
  alias Botyaga.Companies.Location

  setup do
    {:ok, user} =
      Accounts.create_user("audit@baga.example", "Одит", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, comp_a, _} = Companies.create(%{"name" => "Фирма А", "eik" => "111000111"}, user)
    {:ok, comp_b, _} = Companies.create(%{"name" => "Фирма Б", "eik" => "222000222"}, user)
    Companies.set_active(user.username, comp_a.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})
    {:ok, user: user, conn: conn, a: comp_a, b: comp_b, by_number: by_number}
  end

  # Продукт, сметка 304 и складов обект в ЧУЖДАТА фирма Б.
  defp foreign_assets(user, b, a) do
    Companies.set_active(user.username, b.id)
    conn_b = auth_conn(build_conn(), user)
    accounts_b = json_response(get(conn_b, "/v1/accounts?limit=500"), 200)["items"]
    acc_b = Enum.find(accounts_b, &(&1["number"] == "304"))

    prod_b =
      json_response(
        post(conn_b, "/v1/products", %{
          "name" => "Чужд продукт",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => acc_b["id"]
        }),
        201
      )

    loc_b =
      json_response(
        post(conn_b, "/v1/companies/#{b.id}/locations", %{"name" => "Чужд склад"}),
        201
      )

    Companies.set_active(user.username, a.id)
    %{product: prod_b, account: acc_b, location: loc_b}
  end

  describe "IDOR: референции към чужда фирма се отказват" do
    test "производствена карта: чужд product_id при създаване", %{
      conn: conn,
      user: user,
      a: a,
      b: b
    } do
      foreign = foreign_assets(user, b, a)

      conn =
        post(conn, "/v1/production-cards", %{
          "month" => "2026-03",
          "products" => [%{"product_id" => foreign.product["id"], "quantity" => "1"}]
        })

      assert json_response(conn, 422)["detail"] == "стоката не е намерена"
    end

    test "производствена карта: чужда сметка при промяна", %{
      conn: conn,
      user: user,
      a: a,
      b: b
    } do
      foreign = foreign_assets(user, b, a)
      card = json_response(post(conn, "/v1/production-cards", %{"month" => "2026-03"}), 201)

      conn =
        patch(conn, "/v1/production-cards/#{card["id"]}", %{
          "materials_account_id" => foreign.account["id"]
        })

      assert json_response(conn, 422)["detail"] == "сметката не е намерена във фирмата"
    end

    test "ДДС операция с чужда ДДС сметка", %{conn: conn, user: user, a: a, b: b} do
      foreign = foreign_assets(user, b, a)

      conn =
        post(conn, "/v1/vat/operations", %{
          "name" => "Чужда операция",
          "category" => "sales",
          "code" => 1,
          "vat_account_id" => foreign.account["id"]
        })

      assert json_response(conn, 422)["detail"] == "сметката не е намерена във фирмата"
    end

    test "OSS ставка с чужда аналитична сметка", %{conn: conn, user: user, a: a, b: b} do
      foreign = foreign_assets(user, b, a)

      conn =
        post(conn, "/v1/oss/rates", %{
          "country" => "DE",
          "rate" => "19",
          "account_id" => foreign.account["id"]
        })

      assert json_response(conn, 422)["detail"] == "сметката не е намерена във фирмата"
    end

    test "комплектоване с чужд складов обект", %{
      conn: conn,
      user: user,
      a: a,
      b: b,
      by_number: by_number
    } do
      foreign = foreign_assets(user, b, a)

      own =
        json_response(
          post(conn, "/v1/products", %{
            "name" => "Пакет",
            "product_type" => "30",
            "is_inventory" => true,
            "inventory_account_id" => by_number["304"]
          }),
          201
        )

      conn =
        post(conn, "/v1/kits", %{
          "doc_date" => "2026-11-10",
          "output_product_id" => own["id"],
          "location_id" => foreign.location["id"],
          "lines" => []
        })

      assert json_response(conn, 404)["detail"] == "обектът не е намерен"
    end
  end

  describe "начални салда: валидация на паричните полета" do
    test "невалидна сума и двете страни — при create и update", %{
      conn: conn,
      by_number: by_number
    } do
      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "abc"
        })

      assert json_response(conn, 422)["detail"] == "невалидна сума в дебит"

      conn =
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "100.00",
          "credit" => "5.00"
        })

      assert json_response(conn, 422)["detail"] ==
               "салдото е или дебит, или кредит — не и двете"

      json_response(
        post(conn, "/v1/opening-balances", %{
          "fiscal_year" => 2026,
          "account_id" => by_number["501"],
          "debit" => "100.00"
        }),
        201
      )

      row =
        json_response(get(conn, "/v1/opening-balances?fiscal_year=2026"), 200)["items"]
        |> Enum.find(&(&1["debit"] == "100.00"))

      conn = patch(conn, "/v1/opening-balances/#{row["id"]}", %{"debit" => "abc"})
      assert json_response(conn, 422)["detail"] == "невалидна сума в дебит"

      conn =
        patch(conn, "/v1/opening-balances/#{row["id"]}", %{"debit" => "5.00", "credit" => "5.00"})

      assert json_response(conn, 422)["detail"] ==
               "салдото е или дебит, или кредит — не и двете"
    end
  end

  describe "content-disposition при изтегляне" do
    test "ASCII име — без промяна; кирилица — ASCII fallback + RFC 5987 filename*; кавички/контролни знаци се чистят" do
      conn = BotyagaWeb.Respond.attachment(build_conn(), "x", "text/plain", "DEKLAR.TXT")

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="DEKLAR.TXT")
             ]

      conn = BotyagaWeb.Respond.attachment(build_conn(), "x", "application/pdf", "фактура №1.pdf")
      [header] = get_resp_header(conn, "content-disposition")
      assert header =~ ~r/^attachment; filename="[\x20-\x7E]*"; filename\*=UTF-8''/
      refute header =~ "фактура"

      conn = BotyagaWeb.Respond.attachment(build_conn(), "x", "text/plain", "a\"b\r\nc.txt")
      [header] = get_resp_header(conn, "content-disposition")
      assert header == ~s(attachment; filename="a'bc.txt")
    end
  end

  describe "изтриване на потребител и фирма" do
    test "delete_user чисти и членствата (user_companies)", %{a: a} do
      {:ok, u2} = Accounts.create_user("del@baga.example", "Дел", "парола-123")
      {:ok, role_id} = Access.role_id_by_name(Access.role_admin())
      Access.grant(u2.id, a.id, role_id)
      assert Repo.get_by(Membership, user_id: u2.id, company_id: a.id)

      Accounts.delete_user(u2)
      refute Repo.get_by(Membership, user_id: u2.id, company_id: a.id)
      refute Repo.get_by(Accounts.User, id: u2.id)
    end

    test "изтриване на фирма изтрива и зависимите редове (FK cascade)", %{
      conn: conn,
      user: user,
      a: a
    } do
      loc =
        json_response(post(conn, "/v1/companies/#{a.id}/locations", %{"name" => "Склад А"}), 201)

      assert Repo.get_by(Location, id: loc["id"], company_id: a.id)

      conn = delete(conn, "/v1/companies/#{a.id}")
      assert conn.status in [200, 204]
      refute Repo.get_by(Location, id: loc["id"])
      refute Repo.get_by(Companies.Company, id: a.id)
      _ = user
    end
  end
end

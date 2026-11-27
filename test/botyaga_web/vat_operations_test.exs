defmodule BotyagaWeb.VatOperationsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}
  alias Botyaga.Vat.Operations

  setup do
    {:ok, user} =
      Accounts.create_user("vops@baga.example", "ВО", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "ВО ООД", "eik" => "207111222"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    {:ok, conn: conn, company: company}
  end

  test "нова фирма получава готовите операции", %{company: company} do
    ops = Operations.list(company.id)
    assert length(ops) >= 20
    assert Enum.any?(ops, &(&1.category == "purchase" and &1.code == 1 and &1.rate == "20"))
    assert Enum.any?(ops, &(&1.category == "sales" and &1.code == 4))
  end

  test "CRUD и уникално име за категория", %{conn: conn} do
    conn =
      post(conn, "/v1/vat/operations", %{
        "name" => "Моя операция",
        "category" => "sales",
        "code" => 1,
        "rate" => "20"
      })

    op = json_response(conn, 201)
    assert op["category"] == "sales"

    # същото име за същата категория се отказва
    conn =
      post(conn, "/v1/vat/operations", %{
        "name" => "Моя операция",
        "category" => "sales",
        "code" => 1,
        "rate" => "20"
      })

    assert json_response(conn, 422)

    # редакция: сметки и протокол
    conn = patch(conn, "/v1/vat/operations/#{op["id"]}", %{"protocol" => "чл. 117"})
    assert json_response(conn, 200)["protocol"] == "чл. 117"

    conn = delete(conn, "/v1/vat/operations/#{op["id"]}")
    assert response(conn, 204)
  end

  test "resolver по фактура и ставка", %{company: company} do
    inv = %{direction: "in", document_type: "01", vat_article: "", vat_exemption_reason: ""}
    op = Operations.for_invoice(company.id, inv, "20")
    assert op.category == "purchase" and op.code == 1 and op.rate == "20"

    sales = %{direction: "out", document_type: "01", vat_article: "", vat_exemption_reason: ""}
    assert Operations.for_invoice(company.id, sales, "9").code == 2
  end

  test "сметка от операцията управлява осчетоводяването", %{conn: conn, company: company} do
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    # нова ДДС сметка за продажби, различна от 4532
    alt =
      json_response(
        post(conn, "/v1/accounts", %{"number" => "45329", "name" => "Алт ДДС продажби"}),
        201
      )

    op =
      Operations.for_invoice(
        company.id,
        %{direction: "out", document_type: "01", vat_article: "", vat_exemption_reason: ""},
        "20"
      )

    {:ok, _} = Operations.update(op, %{"vat_account_id" => alt["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "111222333"}),
        201
      )

    product =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Услуга",
          "product_type" => "30",
          "is_inventory" => false
        }),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => "S-1",
          "issue_date" => "2026-11-10",
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => product["id"],
              "description" => "У",
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

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
    entry = json_response(get(conn, "/v1/journal/#{shown["journal_entry_id"]}"), 200)
    nums = Enum.map(entry["lines"], & &1["account_number"])
    assert "45329" in nums
    refute "4532" in nums
    assert "411" in nums
    _ = by_number
  end
end

defmodule BotyagaWeb.KitsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("kit@baga.example", "КП", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "КП ООД", "eik" => "207888999"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    loc =
      json_response(
        post(conn, "/v1/companies/#{company.id}/locations", %{"name" => "Склад"}),
        201
      )

    {:ok, conn: conn, company: company, by_number: by_number, loc: loc}
  end

  test "комплектоване на стоки: Дт комплект / Кт съставка, без 611", %{
    conn: conn,
    by_number: by_number,
    loc: loc
  } do
    comp =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока А",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    kitp =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Пакет",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    # покупка 10 бр × 10 = 100 → себестойност 10/бр
    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => "P-1",
          "issue_date" => "2026-11-01",
          "counterpart_id" => cp["id"],
          "location_id" => loc["id"],
          "lines" => [
            %{
              "product_id" => comp["id"],
              "description" => "А",
              "quantity" => "10",
              "unit_price" => "10.00",
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

    kit =
      json_response(
        post(conn, "/v1/kits", %{
          "doc_date" => "2026-11-10",
          "kind" => "kit_goods",
          "output_product_id" => kitp["id"],
          "quantity" => "1",
          "location_id" => loc["id"],
          "lines" => [%{"product_id" => comp["id"], "quantity" => "2"}]
        }),
        201
      )

    conf = json_response(post(conn, "/v1/kits/#{kit["id"]}/confirm", %{}), 200)
    assert conf["status"] == "completed"
    assert conf["cost"] == "20.00"

    entry = json_response(get(conn, "/v1/journal/#{conf["journal_entry_id"]}"), 200)
    assert entry["document_type"] == "kit"
    dirs = Enum.map(entry["lines"], &{&1["account_number"], &1["direction"], &1["amount"]})
    assert {"304", "debit", "20.00"} in dirs
    assert {"304", "credit", "20.00"} in dirs
    refute Enum.any?(entry["lines"], &(&1["account_number"] == "611"))
  end

  test "собствен продукт не може в комплект от стоки", %{
    conn: conn,
    by_number: by_number,
    loc: loc
  } do
    own =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Продукт",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"],
          "revenue_account_id" => by_number["701"]
        }),
        201
      )

    kitp =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Пакет",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    conn =
      post(conn, "/v1/kits", %{
        "doc_date" => "2026-11-10",
        "kind" => "kit_goods",
        "output_product_id" => kitp["id"],
        "quantity" => "1",
        "location_id" => loc["id"],
        "lines" => [%{"product_id" => own["id"], "quantity" => "1"}]
      })

    assert json_response(conn, 422)["detail"] =~ "собствен продукт"
  end
end

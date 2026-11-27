defmodule BotyagaWeb.ProductionReceiptsWipTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("prw@baga.example", "ПРW", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} =
      Companies.create(
        %{
          "name" => "ПРW ООД",
          "eik" => "207777888",
          "accountant_name" => "Иван",
          "accountant_egn" => "8001010000"
        },
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

    {:ok, conn: conn, company: company, by_number: by_number, cp: cp}
  end

  defp product(conn, by_number, name) do
    json_response(
      post(conn, "/v1/products", %{
        "name" => name,
        "product_type" => "20",
        "is_inventory" => true,
        "inventory_account_id" => by_number["303"],
        "revenue_account_id" => by_number["701"],
        "expense_account_id" => by_number["611"]
      }),
      201
    )
  end

  defp sale(conn, _by_number, product, qty, cp) do
    net = qty * 300

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => "S-W",
          "issue_date" => "2026-11-10",
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => product["id"],
              "description" => "Продажба",
              "quantity" => "#{qty}",
              "unit_price" => "300.00",
              "vat_rate" => "20",
              "net_amount" => "#{net}.00",
              "vat_amount" => "#{net * 0.2}",
              "total_amount" => "#{net * 1.2}"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
  end

  test "незавършено производство: част от 611 остава за следващия месец", %{
    conn: conn,
    by_number: by_number,
    cp: cp
  } do
    p = product(conn, by_number, "Изделие")
    sale(conn, by_number, p, 4, cp)

    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => "2026-11-12",
        "description" => "разход",
        "lines" => [
          %{"account_id" => by_number["611"], "direction" => "debit", "amount" => "350.00"},
          %{"account_id" => by_number["401"], "direction" => "credit", "amount" => "350.00"}
        ]
      }),
      201
    )

    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-11",
          "wip_end_mode" => "amount",
          "wip_end_value" => "70.00",
          "lines" => [%{"product_id" => p["id"], "ending_quantity" => "3"}]
        }),
        201
      )

    # produced 7, available 350-70=280 → unit 40, amount 280
    assert hd(doc["lines"])["amount"] == "280.00"

    conf = json_response(post(conn, "/v1/production-receipts/#{doc["id"]}/confirm", %{}), 200)
    entry = json_response(get(conn, "/v1/journal/#{conf["journal_entry_id"]}"), 200)
    by_acc = Enum.group_by(entry["lines"], & &1["account_number"])

    credit611 =
      Enum.reduce(by_acc["611"], 0, fn l, a ->
        a + if(l["direction"] == "credit", do: String.to_float(l["amount"]), else: 0)
      end)

    assert credit611 == 280.0
  end

  test "ръчна сума и коефициент разпределят стойността", %{
    conn: conn,
    by_number: by_number,
    cp: cp
  } do
    p1 = product(conn, by_number, "А")
    p2 = product(conn, by_number, "Б")
    sale(conn, by_number, p1, 1, cp)
    sale(conn, by_number, p2, 1, cp)

    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => "2026-11-12",
        "description" => "разход",
        "lines" => [
          %{"account_id" => by_number["611"], "direction" => "debit", "amount" => "100.00"},
          %{"account_id" => by_number["401"], "direction" => "credit", "amount" => "100.00"}
        ]
      }),
      201
    )

    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-11",
          "lines" => [
            %{"product_id" => p1["id"], "ending_quantity" => "0", "manual_amount" => "60.00"},
            %{"product_id" => p2["id"], "ending_quantity" => "0"}
          ]
        }),
        201
      )

    costs = Map.new(doc["lines"], fn l -> {l["product_id"], l["amount"]} end)
    assert costs[p1["id"]] == "60.00"
    assert costs[p2["id"]] == "40.00"
  end
end

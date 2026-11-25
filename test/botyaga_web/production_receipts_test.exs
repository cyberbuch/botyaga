defmodule BotyagaWeb.ProductionReceiptsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("pr@baga.example", "ПР", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "ПР ООД", "eik" => "207999888"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    # подсметки на 612: 61201 преки, 61202 непреки
    json_response(
      post(conn, "/v1/accounts", %{
        "number" => "61201",
        "name" => "Преки разходи за спомагателна дейност"
      }),
      201
    )

    a61202 =
      json_response(
        post(conn, "/v1/accounts", %{
          "number" => "61202",
          "name" => "Непреки разходи за спомагателна дейност"
        }),
        201
      )

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
        201
      )

    customer =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "222333444"}),
        201
      )

    # продукция: 303 / 701 / 611 от настройките на артикула, себестойност 50
    product =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Изделие А",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"],
          "revenue_account_id" => by_number["701"],
          "expense_account_id" => by_number["611"],
          "cost_price" => "50.00"
        }),
        201
      )

    {:ok,
     conn: conn,
     company: company,
     by_number: by_number,
     cp: cp,
     customer: customer,
     product: product,
     a61202: a61202}
  end

  defp sale(conn, customer, product, qty, date, number) do
    price = 300.0
    net = :erlang.float_to_binary(qty * price, decimals: 2)
    vat = :erlang.float_to_binary(qty * price * 0.2, decimals: 2)
    total = :erlang.float_to_binary(qty * price * 1.2, decimals: 2)

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => number,
          "issue_date" => date,
          "counterpart_id" => customer["id"],
          "lines" => [
            %{
              "product_id" => product["id"],
              "description" => "Продажба",
              "quantity" => "#{qty}",
              "unit_price" => "300.00",
              "vat_rate" => "20",
              "net_amount" => net,
              "vat_amount" => vat,
              "total_amount" => total
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    inv
  end

  defp manual_journal(conn, debit_acc, credit_acc, amount, date) do
    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => date,
        "description" => "Ръчен запис",
        "lines" => [
          %{"account_id" => debit_acc, "direction" => "debit", "amount" => amount},
          %{"account_id" => credit_acc, "direction" => "credit", "amount" => amount}
        ]
      }),
      201
    )
  end

  defp sum_amounts(lines, direction) do
    lines
    |> Enum.filter(&(&1["direction"] == direction))
    |> Enum.reduce(0.0, fn l, s -> s + String.to_float(l["amount"]) end)
  end

  test "преглед → документ → потвърждаване → записи (ДТ 303 КТ 611, ДТ 303 КТ 61202, ДТ 701 КТ 303)",
       %{conn: conn, by_number: by_number, customer: customer, product: product, a61202: a61202} do
    sale(conn, customer, product, 4, "2026-02-10", "S-1")

    # натрупана стойност в 611 за месеца (преки производствени разходи)
    manual_journal(conn, by_number["611"], by_number["401"], "350.00", "2026-02-12")
    # непреки разходи по 61202
    manual_journal(conn, a61202["id"], by_number["401"], "200.00", "2026-02-15")

    # Таб 1: продаденото по КТ 701 + натрупаната стойност в 611 (4 × 50)
    prev = json_response(get(conn, "/v1/production-receipts/preview?month=2026-02"), 200)
    assert prev["month"] == "2026-02"
    assert prev["doc_date"] == "2026-02-28"
    assert length(prev["lines"]) == 1

    assert prev["expense_total"] == "350.00"
    line = hd(prev["lines"])
    assert line["product_id"] == product["id"]
    assert line["sold_quantity"] == "4.0000"
    assert line["sold_revenue"] == "1200.00"

    # в прегледа единичната цена е 611 / продадено (наличност още не е зададена)
    assert line["sold_amount"] == "350.00"
    assert line["unit_cost"] == "87.500000"
    assert line["inventory_account_id"] == by_number["303"]
    assert line["revenue_account_id"] == by_number["701"]
    assert line["expense_account_id"] == by_number["611"]

    # Таб 2: натрупаните непреки разходи по 612 (без 61201)
    ind = Enum.find(prev["indirect"], &(&1["number"] == "61202"))
    assert ind["amount"] == "200.00"

    # Създаване с наличност 3 → произведено = 4 + 3 = 7
    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-02",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "3"}]
        }),
        201
      )

    assert doc["status"] == "draft"
    assert doc["month"] == "2026-02"
    assert doc["doc_date"] == "2026-02-28"
    assert [l] = doc["lines"]
    assert l["sold_quantity"] == "4.0000"
    assert l["sold_amount"] == "200.00"
    assert l["ending_quantity"] == "3.0000"
    assert l["quantity"] == "7.0000"
    assert l["unit_cost"] == "50.000000"
    assert l["amount"] == "350.00"

    # Потвърждаване
    confirmed =
      json_response(post(conn, "/v1/production-receipts/#{doc["id"]}/confirm", %{}), 200)

    assert confirmed["status"] == "confirmed"
    entry_id = confirmed["journal_entry_id"]
    assert entry_id > 0

    [l2] = confirmed["lines"]
    # единствен артикул поема цялото разпределение
    assert l2["allocated_amount"] == "200.00"
    # изписване: 4 × (350 + 200) / 7 = 314.2857 → 314.29
    assert l2["writeoff_amount"] == "314.29"
    assert length(confirmed["allocations"]) == 1
    assert hd(confirmed["allocations"])["amount"] == "200.00"

    # Таб 3: записите в дневника
    entry = json_response(get(conn, "/v1/journal/#{entry_id}"), 200)
    assert entry["document_type"] == "production_receipt"
    assert entry["document_id"] == doc["id"]
    lines = entry["lines"]
    by_acc = Enum.group_by(lines, & &1["account_number"])

    assert Enum.any?(by_acc["303"], &(&1["direction"] == "debit" and &1["amount"] == "350.00"))
    assert Enum.any?(by_acc["611"], &(&1["direction"] == "credit" and &1["amount"] == "350.00"))
    assert Enum.any?(by_acc["303"], &(&1["direction"] == "debit" and &1["amount"] == "200.00"))
    assert Enum.any?(by_acc["61202"], &(&1["direction"] == "credit" and &1["amount"] == "200.00"))
    assert Enum.any?(by_acc["701"], &(&1["direction"] == "debit" and &1["amount"] == "314.29"))
    assert Enum.any?(by_acc["303"], &(&1["direction"] == "credit" and &1["amount"] == "314.29"))

    # балансирана статия
    assert sum_amounts(lines, "debit") == sum_amounts(lines, "credit")
  end

  test "update на чернова променя наличността и произведеното",
       %{conn: conn, by_number: by_number, customer: customer, product: product} do
    sale(conn, customer, product, 2, "2026-03-05", "S-2")
    manual_journal(conn, by_number["611"], by_number["401"], "350.00", "2026-03-06")

    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-03",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "1"}]
        }),
        201
      )

    assert hd(doc["lines"])["quantity"] == "3.0000"

    updated =
      json_response(
        patch(conn, "/v1/production-receipts/#{doc["id"]}", %{
          "notes" => "бракувани 2 бр.",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "5"}]
        }),
        200
      )

    assert updated["notes"] == "бракувани 2 бр."
    assert hd(updated["lines"])["ending_quantity"] == "5.0000"
    assert hd(updated["lines"])["quantity"] == "7.0000"
    assert hd(updated["lines"])["amount"] == "350.00"
  end

  test "втори потвърден документ за същия месец е 409",
       %{conn: conn, by_number: by_number, customer: customer, product: product} do
    sale(conn, customer, product, 2, "2026-04-05", "S-3")
    manual_journal(conn, by_number["611"], by_number["401"], "100.00", "2026-04-06")

    doc1 =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-04",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "0"}]
        }),
        201
      )

    doc2 =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-04",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "1"}]
        }),
        201
      )

    json_response(post(conn, "/v1/production-receipts/#{doc1["id"]}/confirm", %{}), 200)

    conn = post(conn, "/v1/production-receipts/#{doc2["id"]}/confirm", %{})
    assert json_response(conn, 409)["detail"] =~ "вече има потвърден"
  end

  test "unpost връща в чернова и изтрива journal записа",
       %{conn: conn, by_number: by_number, customer: customer, product: product} do
    sale(conn, customer, product, 3, "2026-05-05", "S-4")
    manual_journal(conn, by_number["611"], by_number["401"], "150.00", "2026-05-06")

    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-05",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "2"}]
        }),
        201
      )

    confirmed =
      json_response(post(conn, "/v1/production-receipts/#{doc["id"]}/confirm", %{}), 200)

    entry_id = confirmed["journal_entry_id"]
    assert entry_id > 0

    back = json_response(post(conn, "/v1/production-receipts/#{doc["id"]}/unpost", %{}), 200)
    assert back["status"] == "draft"
    assert back["journal_entry_id"] == 0
    assert back["allocations"] == []
    assert hd(back["lines"])["writeoff_amount"] == "0.00"

    conn = get(conn, "/v1/journal/#{entry_id}")
    assert json_response(conn, 404)

    # потвърден документ не се редактира
    json_response(post(conn, "/v1/production-receipts/#{doc["id"]}/confirm", %{}), 200)
    conn = patch(conn, "/v1/production-receipts/#{doc["id"]}", %{"notes" => "x"})
    assert json_response(conn, 409)
  end

  test "месец без продажби → 422 при създаване", %{conn: conn} do
    conn = post(conn, "/v1/production-receipts", %{"month" => "2026-06"})
    assert json_response(conn, 422)["detail"] =~ "няма артикули"
  end

  test "невалиден месец → 422", %{conn: conn} do
    conn = get(conn, "/v1/production-receipts/preview?month=2026-13")
    assert json_response(conn, 422)
  end

  test "изтриване само на чернова", %{
    conn: conn,
    by_number: by_number,
    customer: customer,
    product: product
  } do
    sale(conn, customer, product, 1, "2026-07-05", "S-5")
    manual_journal(conn, by_number["611"], by_number["401"], "50.00", "2026-07-06")

    doc =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-07",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "0"}]
        }),
        201
      )

    conn = delete(conn, "/v1/production-receipts/#{doc["id"]}")
    assert response(conn, 204)

    doc2 =
      json_response(
        post(conn, "/v1/production-receipts", %{
          "month" => "2026-07",
          "lines" => [%{"product_id" => product["id"], "ending_quantity" => "0"}]
        }),
        201
      )

    json_response(post(conn, "/v1/production-receipts/#{doc2["id"]}/confirm", %{}), 200)
    conn = delete(conn, "/v1/production-receipts/#{doc2["id"]}")
    assert json_response(conn, 409)
  end
end

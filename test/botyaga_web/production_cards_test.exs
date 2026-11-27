defmodule BotyagaWeb.ProductionCardsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("pc@baga.example", "ПК", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "ПК ООД", "eik" => "207555666"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    by_number =
      Enum.reduce(["601", "602", "603", "501", "302", "303", "611"], by_number, fn n, acc ->
        if Map.has_key?(acc, n) do
          acc
        else
          a =
            json_response(
              post(conn, "/v1/accounts", %{"number" => n, "name" => "Сметка #{n}"}),
              201
            )

          Map.put(acc, n, a["id"])
        end
      end)

    {:ok, conn: conn, company: company, by_number: by_number}
  end

  defp journal(conn, by_number, debit, credit, amount, date) do
    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => date,
        "description" => "разход",
        "lines" => [
          %{"account_id" => by_number[debit], "direction" => "debit", "amount" => amount},
          %{"account_id" => by_number[credit], "direction" => "credit", "amount" => amount}
        ]
      }),
      201
    )
  end

  test "месечна карта: материали + преки + общи, незавършено, разпределение и статии", %{
    conn: conn,
    by_number: by_number
  } do
    product =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Изделие",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"]
        }),
        201
      )

    # материали 601 = 100, преки 602 = 50, общи 603 = 30
    journal(conn, by_number, "601", "302", "100.00", "2026-11-05")
    journal(conn, by_number, "602", "501", "50.00", "2026-11-06")
    journal(conn, by_number, "603", "501", "30.00", "2026-11-07")

    card =
      json_response(
        post(conn, "/v1/production-cards", %{
          "month" => "2026-11",
          "products" => [
            %{"product_id" => product["id"], "quantity" => "10", "coefficient" => "1"}
          ]
        }),
        201
      )

    conn =
      patch(conn, "/v1/production-cards/#{card["id"]}", %{
        "direct_accounts" => [by_number["602"]],
        "common_accounts" => [by_number["603"]],
        "common_share_percent" => "100",
        "wip_end_mode" => "amount",
        "wip_end_value" => "20.00"
      })

    card = json_response(conn, 200)
    pv = json_response(get(conn, "/v1/production-cards/#{card["id"]}/preview"), 200)
    assert pv["materials"] == "100.00"
    assert pv["common_share"] == "30.00"
    assert pv["wip_end"] == "20.00"
    # 100 + 50 + 30 + 0 - 20 = 160
    assert pv["total"] == "160.00"
    assert hd(pv["products"])["cost"] == "160.00"

    conf = json_response(post(conn, "/v1/production-cards/#{card["id"]}/confirm", %{}), 200)
    assert conf["status"] == "confirmed"
    entry = json_response(get(conn, "/v1/journal/#{conf["journal_entry_id"]}"), 200)
    by_acc = Enum.group_by(entry["lines"], & &1["account_number"])
    assert Enum.any?(by_acc["611"], &(&1["direction"] == "debit" and &1["amount"] == "100.00"))
    assert Enum.any?(by_acc["601"], &(&1["direction"] == "credit"))
    assert Enum.any?(by_acc["303"], &(&1["direction"] == "debit" and &1["amount"] == "160.00"))
    # в 611 остава крайното незавършено 20
    debit611 =
      Enum.reduce(by_acc["611"], 0, fn l, a ->
        a + if(l["direction"] == "debit", do: String.to_float(l["amount"]), else: 0)
      end)

    credit611 =
      Enum.reduce(by_acc["611"], 0, fn l, a ->
        a + if(l["direction"] == "credit", do: String.to_float(l["amount"]), else: 0)
      end)

    assert debit611 - credit611 == 20.0
  end

  test "ръчно разпределение по сума на продукт", %{conn: conn, by_number: by_number} do
    p1 =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "А",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"]
        }),
        201
      )

    p2 =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Б",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"]
        }),
        201
      )

    journal(conn, by_number, "601", "302", "100.00", "2026-11-05")

    card =
      json_response(
        post(conn, "/v1/production-cards", %{
          "month" => "2026-11",
          "products" => [
            %{"product_id" => p1["id"], "quantity" => "1", "manual_amount" => "60.00"},
            %{"product_id" => p2["id"], "quantity" => "1"}
          ]
        }),
        201
      )

    pv = json_response(get(conn, "/v1/production-cards/#{card["id"]}/preview"), 200)
    costs = Map.new(pv["products"], &{&1["name"], &1["cost"]})
    assert costs["А"] == "60.00"
    assert costs["Б"] == "40.00"
  end
end

defmodule BotyagaWeb.ProductionCardLinkTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies, Repo}
  alias Botyaga.Production.Order

  setup do
    {:ok, user} =
      Accounts.create_user("lnk@baga.example", "ЛН", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "ЛН ООД", "eik" => "207222111"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    by_number =
      Enum.reduce(["602", "501", "611", "302", "303"], by_number, fn n, acc ->
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

  test "закачени поръчки поемат преките/общите разходи в края на месеца", %{
    conn: conn,
    by_number: bn,
    company: company
  } do
    mat =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "М",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => bn["302"]
        }),
        201
      )

    out =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "И",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => bn["303"]
        }),
        201
      )

    recipe =
      json_response(
        post(conn, "/v1/recipes", %{
          "name" => "Р",
          "output_product_id" => out["id"],
          "output_quantity" => "1",
          "lines" => [%{"product_id" => mat["id"], "quantity" => "1", "unit" => "бр"}]
        }),
        201
      )

    loc =
      json_response(post(conn, "/v1/companies/#{company.id}/locations", %{"name" => "Цех"}), 201)

    order =
      json_response(
        post(conn, "/v1/production-orders", %{
          "recipe_id" => recipe["id"],
          "quantity" => "2",
          "order_date" => "2026-11-05",
          "location_id" => loc["id"]
        }),
        201
      )

    # маркираме като потвърдена със себестойност 100 (за теста)
    Repo.get(Order, order["id"])
    |> Ecto.Changeset.change(status: "completed", material_cost: "100.00")
    |> Repo.update!()

    # преки разходи 602 = 50
    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => "2026-11-20",
        "description" => "заплата",
        "lines" => [
          %{"account_id" => bn["602"], "direction" => "debit", "amount" => "50.00"},
          %{"account_id" => bn["501"], "direction" => "credit", "amount" => "50.00"}
        ]
      }),
      201
    )

    card =
      json_response(
        post(conn, "/v1/production-cards", %{"month" => "2026-11", "kind" => "recipes"}),
        201
      )

    assert card["kind"] == "recipes"

    linkable =
      json_response(get(conn, "/v1/production-cards/#{card["id"]}/linkable"), 200)["items"]

    assert Enum.any?(linkable, &(&1["id"] == order["id"]))

    json_response(
      post(conn, "/v1/production-orders/#{order["id"]}/link", %{"card_id" => card["id"]}),
      200
    )

    conn =
      patch(conn, "/v1/production-cards/#{card["id"]}", %{
        "direct_accounts" => [bn["602"]],
        "common_share_percent" => "100"
      })

    card = json_response(conn, 200)

    pv = json_response(get(conn, "/v1/production-cards/#{card["id"]}/preview"), 200)
    assert pv["total"] == "50.00"
    assert hd(pv["products"])["cost"] == "50.00"

    conf = json_response(post(conn, "/v1/production-cards/#{card["id"]}/confirm", %{}), 200)
    entry = json_response(get(conn, "/v1/journal/#{conf["journal_entry_id"]}"), 200)
    dirs = Enum.map(entry["lines"], &{&1["account_number"], &1["direction"], &1["amount"]})

    # добавените разходи: Дт 303 (продукта на поръчката) / Кт 611
    assert {"303", "debit", "50.00"} in dirs
    assert {"611", "credit", "50.00"} in dirs
    # прехвърляне на прекия разход: Дт 611 / Кт 602
    assert {"611", "debit", "50.00"} in dirs
    assert {"602", "credit", "50.00"} in dirs
  end
end

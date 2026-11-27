defmodule BotyagaWeb.ProductionCopyTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("cpy@baga.example", "КП", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} = Companies.create(%{"name" => "КП ООД", "eik" => "207111000"}, user)
    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    loc =
      json_response(post(conn, "/v1/companies/#{company.id}/locations", %{"name" => "Цех"}), 201)

    {:ok, conn: conn, company: company, by_number: by_number, loc: loc}
  end

  test "копиране и приложена рецепта с история на нормите", %{conn: conn, by_number: bn, loc: loc} do
    mat =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Материал",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => bn["302"]
        }),
        201
      )

    out =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Изделие",
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
          "lines" => [
            %{
              "product_id" => mat["id"],
              "quantity" => "2",
              "unit" => "бр",
              "wastage_percent" => "0"
            }
          ]
        }),
        201
      )

    order =
      json_response(
        post(conn, "/v1/production-orders", %{
          "recipe_id" => recipe["id"],
          "quantity" => "3",
          "order_date" => "2026-11-01",
          "location_id" => loc["id"]
        }),
        201
      )

    # норма 2×3=6, запазена като снимка
    assert hd(order["lines"])["norm_quantity"] == "6.0000"
    assert order["recipe_snapshot"]["lines"] |> hd() |> Map.get("quantity") == "2.0000"

    # промяна на рецептата НЕ променя историята на поръчката
    patch(conn, "/v1/recipes/#{recipe["id"]}", %{
      "lines" => [
        %{"product_id" => mat["id"], "quantity" => "5", "unit" => "бр", "wastage_percent" => "0"}
      ]
    })

    again = json_response(get(conn, "/v1/production-orders/#{order["id"]}"), 200)
    assert hd(again["lines"])["norm_quantity"] == "6.0000"

    # копиране: нов запис с днешна дата и норми по текущата рецепта (5×3=15)
    copy = json_response(post(conn, "/v1/production-orders/#{order["id"]}/copy", %{}), 201)
    assert copy["id"] != order["id"]
    assert copy["order_date"] == Date.to_iso8601(Date.utc_today())
    assert hd(copy["lines"])["norm_quantity"] == "15.0000"
  end
end

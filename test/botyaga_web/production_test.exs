defmodule BotyagaWeb.ProductionTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("prod@baga.example", "Производство", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Производство ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    location =
      json_response(
        post(conn, "/v1/companies/#{company.id}/locations", %{
          "name" => "Цех",
          "location_type" => "WAREHOUSE"
        }),
        201
      )

    location2 =
      json_response(
        post(conn, "/v1/companies/#{company.id}/locations", %{
          "name" => "Склад",
          "location_type" => "WAREHOUSE"
        }),
        201
      )

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
        201
      )

    material =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Материал",
          "product_type" => "10",
          "is_inventory" => true,
          "inventory_account_id" => by_number["302"],
          "revenue_account_id" => by_number["702"],
          "expense_account_id" => by_number["60101"]
        }),
        201
      )

    output =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Продукция",
          "product_type" => "20",
          "is_inventory" => true,
          "inventory_account_id" => by_number["303"],
          "revenue_account_id" => by_number["703"]
        }),
        201
      )

    {:ok,
     conn: conn,
     company: company,
     by_number: by_number,
     location: location,
     location2: location2,
     cp: cp,
     material: material,
     output: output}
  end

  defp purchase(conn, cp, product, qty, price, date, number, location_id \\ 0) do
    net = :erlang.float_to_binary(qty * price, decimals: 2)
    vat = :erlang.float_to_binary(qty * price * 0.2, decimals: 2)
    total = :erlang.float_to_binary(qty * price * 1.2, decimals: 2)

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "in",
          "number" => number,
          "issue_date" => date,
          "counterpart_id" => cp["id"],
          "location_id" => location_id,
          "lines" => [
            %{
              "product_id" => product["id"],
              "description" => "Покупка",
              "quantity" => "#{qty}",
              "unit_price" => :erlang.float_to_binary(price, decimals: 2),
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
  end

  describe "рецепти и поръчки" do
    test "рецепта, поръчка и потвърждение със себестойност", %{
      conn: conn,
      by_number: by_number,
      location: location,
      cp: cp,
      material: material,
      output: output
    } do
      purchase(conn, cp, material, 100, 10.0, "2026-01-01", "P-1")

      recipe =
        json_response(
          post(conn, "/v1/recipes", %{
            "name" => "Рецепта 1",
            "output_product_id" => output["id"],
            "output_quantity" => "10",
            "lines" => [
              %{
                "product_id" => material["id"],
                "quantity" => "5",
                "unit" => "KGM",
                "wastage_percent" => "0"
              }
            ]
          }),
          201
        )

      assert length(recipe["lines"]) == 1

      order =
        json_response(
          post(conn, "/v1/production-orders", %{
            "recipe_id" => recipe["id"],
            "quantity" => "20",
            "location_id" => location["id"],
            "order_date" => "2026-01-05"
          }),
          201
        )

      assert order["number"] == "ПР-#{order["id"]}"
      assert order["status"] == "draft"

      # 5 материала за 10 продукция → за 20 продукция = 10 материала
      assert hd(order["lines"])["quantity"] == "10.0000"

      # без правила за продукция потвърждението спира
      conn = post(conn, "/v1/production-orders/#{order["id"]}/confirm", %{})
      assert json_response(conn, 422)["detail"] =~ "няма правило за продукция"

      post(conn, "/v1/stock/rules", %{
        "kind" => "production",
        "inventory_account_id" => by_number["303"],
        "offset_account_id" => by_number["703"],
        "clearing_account_id" => by_number["60101"]
      })

      post(conn, "/v1/stock/rules", %{
        "kind" => "material",
        "inventory_account_id" => by_number["302"],
        "offset_account_id" => by_number["60101"]
      })

      conn = post(conn, "/v1/production-orders/#{order["id"]}/confirm", %{})
      body = json_response(conn, 200)
      assert body["status"] == "completed"
      assert body["material_cost"] == "100.00"
      assert body["journal_entry_id"] > 0
    end

    test "завършена поръчка не се трие", %{
      conn: conn,
      location: location,
      material: material,
      output: output,
      by_number: by_number,
      cp: cp
    } do
      purchase(conn, cp, material, 100, 10.0, "2026-01-01", "P-1")

      post(conn, "/v1/stock/rules", %{
        "kind" => "production",
        "inventory_account_id" => by_number["303"],
        "offset_account_id" => by_number["703"],
        "clearing_account_id" => by_number["60101"]
      })

      post(conn, "/v1/stock/rules", %{
        "kind" => "material",
        "inventory_account_id" => by_number["302"],
        "offset_account_id" => by_number["60101"]
      })

      recipe =
        json_response(
          post(conn, "/v1/recipes", %{
            "name" => "Р",
            "output_product_id" => output["id"],
            "output_quantity" => "1",
            "lines" => [%{"product_id" => material["id"], "quantity" => "1"}]
          }),
          201
        )

      order =
        json_response(
          post(conn, "/v1/production-orders", %{
            "recipe_id" => recipe["id"],
            "quantity" => "1",
            "location_id" => location["id"],
            "order_date" => "2026-01-05"
          }),
          201
        )

      post(conn, "/v1/production-orders/#{order["id"]}/confirm", %{})

      conn = delete(conn, "/v1/production-orders/#{order["id"]}")
      assert json_response(conn, 422)["detail"] == "завършена поръчка не се изтрива"
    end
  end

  describe "ръчно изписване на материали" do
    test "създаване, потвърждение и връщане", %{
      conn: conn,
      by_number: by_number,
      location: location,
      cp: cp,
      material: material
    } do
      purchase(conn, cp, material, 50, 10.0, "2026-01-01", "P-1")

      doc =
        json_response(
          post(conn, "/v1/material-issues", %{
            "doc_date" => "2026-01-10",
            "location_id" => location["id"],
            "lines" => [
              %{
                "product_id" => material["id"],
                "quantity" => "5",
                "account_id" => by_number["60101"],
                "inventory_account_id" => by_number["302"]
              }
            ]
          }),
          201
        )

      assert doc["number"] == "МИ-#{doc["id"]}"
      assert doc["status"] == "draft"

      conn = post(conn, "/v1/material-issues/#{doc["id"]}/confirm", %{})
      body = json_response(conn, 200)
      assert body["status"] == "confirmed"
      assert hd(body["lines"])["amount"] == "50.00"
      assert body["journal_entry_id"] > 0

      conn = post(conn, "/v1/material-issues/#{doc["id"]}/unpost", %{})
      body = json_response(conn, 200)
      assert body["status"] == "draft"
      assert hd(body["lines"])["amount"] == "0.00"
    end
  end

  describe "вътрешни протоколи" do
    test "трансфер на стока между обекти", %{
      conn: conn,
      location: location,
      location2: location2,
      cp: cp,
      material: material
    } do
      purchase(conn, cp, material, 20, 10.0, "2026-01-01", "P-1", location["id"])

      doc =
        json_response(
          post(conn, "/v1/internal-docs", %{
            "doc_date" => "2026-01-15",
            "from_location_id" => location["id"],
            "to_location_id" => location2["id"],
            "lines" => [
              %{"line_kind" => "product", "product_id" => material["id"], "quantity" => "10"}
            ]
          }),
          201
        )

      assert String.length(doc["number"]) == 10

      conn = post(conn, "/v1/internal-docs/#{doc["id"]}/confirm", %{})
      assert json_response(conn, 200)["status"] == "confirmed"

      conn = get(conn, "/v1/inventory/at-location?location_id=#{location2["id"]}")
      assert hd(json_response(conn, 200)["items"])["quantity"] == "10.0000"
    end

    test "трансфер на ДМА мести актива", %{conn: conn, location: location, location2: location2} do
      asset =
        json_response(
          post(conn, "/v1/fixed-assets", %{
            "name" => "Машина",
            "cost" => "1000.00",
            "location_id" => location["id"]
          }),
          201
        )

      doc =
        json_response(
          post(conn, "/v1/internal-docs", %{
            "doc_date" => "2026-01-15",
            "from_location_id" => location["id"],
            "to_location_id" => location2["id"],
            "lines" => [%{"line_kind" => "fixed_asset", "asset_id" => asset["id"]}]
          }),
          201
        )

      post(conn, "/v1/internal-docs/#{doc["id"]}/confirm", %{})
      moved = json_response(get(conn, "/v1/fixed-assets/#{asset["id"]}"), 200)
      assert moved["location_id"] == location2["id"]
    end
  end

  describe "дивиденти" do
    test "разпределение по процент и плащане", %{conn: conn, company: company} do
      post(conn, "/v1/companies/#{company.id}/beneficial-owners", %{
        "first_name_bg" => "Иван",
        "last_name_bg" => "Петров",
        "ownership_percentage" => "60"
      })

      post(conn, "/v1/companies/#{company.id}/beneficial-owners", %{
        "first_name_bg" => "Мария",
        "last_name_bg" => "Иванова",
        "ownership_percentage" => "40"
      })

      dist =
        json_response(
          post(conn, "/v1/dividend-distributions", %{
            "year" => 2026,
            "total_amount" => "1000.00",
            "decision_date" => "2026-03-01",
            "decision_number" => "1"
          }),
          201
        )

      assert dist["status"] == "draft"
      assert dist["dividends_count"] == 2
      assert dist["total_net"] == "950.00"
      assert dist["total_tax"] == "50.00"
      gross = Enum.map(dist["dividends"], & &1["gross_amount"])
      assert gross == ["600.00", "400.00"]

      # плащане само след одобрение
      dividend = hd(dist["dividends"])
      conn = post(conn, "/v1/dividends/#{dividend["id"]}/pay", %{"is_paid" => true})
      assert json_response(conn, 422)["detail"] == "Одобрете разпределението преди изплащане"

      patch(conn, "/v1/dividend-distributions/#{dist["id"]}", %{"status" => "approved"})
      conn = post(conn, "/v1/dividends/#{dividend["id"]}/pay", %{"is_paid" => true})
      body = json_response(conn, 200)
      assert body["status"] == "partially_paid"
    end
  end
end

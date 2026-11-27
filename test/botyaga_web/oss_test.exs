defmodule BotyagaWeb.OssTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("oss@baga.example", "ОСС", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _} =
      Companies.create(
        %{
          "name" => "ОСС ООД",
          "eik" => "207333444",
          "accountant_name" => "Иван",
          "accountant_egn" => "8001010000"
        },
        user
      )

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    {:ok, conn: conn, company: company}
  end

  defp sale(conn, opts) do
    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Население", "eik" => "999999999"}),
        201
      )

    product =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => false
        }),
        201
      )

    json_response(
      post(conn, "/v1/invoices", %{
        "direction" => "out",
        "number" => "OSS-1",
        "issue_date" => "2026-11-10",
        "counterpart_id" => cp["id"],
        "is_oss" => opts[:is_oss] || 0,
        "lines" => [
          %{
            "product_id" => product["id"],
            "description" => "Дистанционна",
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
  end

  test "OSS продажба се отказва без включен режим", %{conn: conn} do
    inv = sale(conn, is_oss: 1)
    conn = post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    assert json_response(conn, 422)["detail"] =~ "OSS"
  end

  test "с включен OSS: ДДС отива в 4534, а не в 4532", %{conn: conn, company: company} do
    patch(conn, "/v1/companies/#{company.id}", %{"oss_enabled" => 1})
    inv = sale(conn, is_oss: 1)
    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})
    shown = json_response(get(conn, "/v1/invoices/#{inv["id"]}"), 200)
    entry = json_response(get(conn, "/v1/journal/#{shown["journal_entry_id"]}"), 200)
    nums = Enum.map(entry["lines"], & &1["account_number"])
    assert "4534" in nums
    refute "4532" in nums
  end

  test "OSS основата е в колона 23 / клетка 18, чуждото ДДС не влиза в българските клетки", %{
    conn: conn,
    company: company
  } do
    patch(conn, "/v1/companies/#{company.id}", %{"oss_enabled" => 1})
    inv = sale(conn, is_oss: 1)
    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

    body = json_response(get(conn, "/v1/vat/registers?period=2026-11"), 200)
    assert body["cells"]["01-18"] == "100.00"

    # чуждото ДДС (20) не участва в българския ДДС за внасяне (01-20)
    assert body["cells"]["01-20"] == "0.00"
    assert Enum.any?(body["sales"], &(&1["base_oss"] == "100.00"))
  end
end

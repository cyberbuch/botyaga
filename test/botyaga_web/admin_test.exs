defmodule BotyagaWeb.AdminTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("admin@baga.example", "Админ", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Админ ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    entry =
      json_response(
        post(conn, "/v1/journal", %{
          "entry_date" => "2026-01-15",
          "description" => "Тестова статия",
          "lines" => [
            %{"account_id" => by_number["411"], "direction" => "debit", "amount" => "100.00"},
            %{"account_id" => by_number["702"], "direction" => "credit", "amount" => "100.00"}
          ]
        }),
        201
      )

    {:ok, conn: conn, company: company, entry: entry}
  end

  describe "audit-logs" do
    test "index и филтри", %{conn: conn} do
      body = json_response(get(conn, "/v1/audit-logs"), 200)
      assert body["count"] >= 1
      first = hd(body["items"])
      assert Map.has_key?(first, "entity_type")
      assert Map.has_key?(first, "user_login")
      assert Map.has_key?(first, "created_at")
      assert Map.has_key?(first, "old_data")

      filtered = json_response(get(conn, "/v1/audit-logs?entity_type=journal&action=create"), 200)

      assert Enum.all?(
               filtered["items"],
               &(&1["entity_type"] == "journal" and &1["action"] == "create")
             )

      none = json_response(get(conn, "/v1/audit-logs?entity_type=nonexistent"), 200)
      assert none["count"] == 0
    end

    test "entity_history", %{conn: conn, entry: entry} do
      body = json_response(get(conn, "/v1/audit-logs/journal/#{entry["id"]}"), 200)
      assert body["count"] >= 1
      assert Enum.all?(body["items"], &(&1["entity_id"] == entry["id"]))
    end
  end

  describe "db-check" do
    test "интегритет на чиста база", %{conn: conn} do
      body = json_response(get(conn, "/v1/system-settings/db-check"), 200)
      assert body["ok"] == true
      assert Map.has_key?(body, "duration_ms")
      ids = Enum.map(body["checks"], & &1["id"])
      assert "connection" in ids
      assert "tables" in ids
      assert "journal_balance" in ids
      assert "orphan_invoices" in ids
      assert Enum.any?(body["tables"], &(&1["name"] == "companies"))
    end
  end

  describe "S3 настройка" do
    test "s3-test без bucket", %{conn: conn} do
      conn = post(conn, "/v1/system-settings/s3-test", %{})
      assert json_response(conn, 422)["detail"] == "S3 bucket е задължителен"
    end

    test "s3-backup и s3-backups без bucket", %{conn: conn} do
      conn = post(conn, "/v1/system-settings/s3-backup", %{})
      assert json_response(conn, 422)["detail"] == "S3 bucket е задължителен"

      conn = get(conn, "/v1/system-settings/s3-backups")
      assert json_response(conn, 422)["detail"] == "S3 bucket е задължителен"
    end

    test "s3-delete валидира ключа", %{conn: conn} do
      conn = post(conn, "/v1/system-settings/s3-delete", %{})
      assert json_response(conn, 422)["detail"] == "s3_key е задължителен"

      conn = post(conn, "/v1/system-settings/s3-delete", %{"s3_key" => "other/file.txt"})
      assert json_response(conn, 400)["detail"] == "ключът не е в папката на ytbuch"

      conn = post(conn, "/v1/system-settings/s3-delete", %{"s3_key" => "backups/notes.txt"})
      assert json_response(conn, 400)["detail"] == "ключът не е архив на ytbuch"
    end
  end
end

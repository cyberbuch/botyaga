defmodule BotyagaWeb.ReportsTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  setup do
    {:ok, user} =
      Accounts.create_user("reports@baga.example", "Справки", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Справки ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Клиент", "eik" => "111222333"}),
        201
      )

    json_response(
      post(conn, "/v1/journal", %{
        "entry_date" => "2026-01-15",
        "document_number" => "J-1",
        "description" => "Продажба",
        "counterpart_id" => cp["id"],
        "lines" => [
          %{"account_id" => by_number["411"], "direction" => "debit", "amount" => "1200.00"},
          %{"account_id" => by_number["702"], "direction" => "credit", "amount" => "1000.00"},
          %{"account_id" => by_number["4532"], "direction" => "credit", "amount" => "200.00"}
        ]
      }),
      201
    )

    {:ok, conn: conn, company: company, by_number: by_number, cp: cp}
  end

  defp report(conn, query), do: json_response(get(conn, "/v1/reports?#{query}"), 200)

  describe "оборотна ведомост" do
    test "салда и обороти", %{conn: conn} do
      body = report(conn, "kind=trial_balance&from=2026-01-01&to=2026-12-31")
      assert body["title"] == "Оборотна ведомост"
      assert body["company_name"] == "Справки ООД"
      rows = Map.new(body["rows"], &{&1["account_number"], &1})
      assert rows["411"]["turnover_debit"] == "1200.00"
      assert rows["702"]["turnover_credit"] == "1000.00"
      assert rows["4532"]["turnover_credit"] == "200.00"
      assert body["totals"]["turnover_debit"] == "1200.00"
      assert body["totals"]["turnover_credit"] == "1200.00"
    end

    test "филтър по сметка дава и нейните контрагенти", %{conn: conn, cp: cp} do
      body = report(conn, "kind=trial_balance&from=2026-01-01&to=2026-12-31&account=70")
      assert body["mode"] == "by_account_cp"
      assert Enum.map(body["rows"], & &1["counterpart_name"]) == [cp["name"]]
      assert Enum.all?(body["rows"], &(&1["account_number"] == "702"))
    end

    test "една сметка плюс избран контрагент", %{conn: conn, cp: cp} do
      body =
        report(
          conn,
          "kind=trial_balance&from=2026-01-01&to=2026-12-31&account=411&counterpart_id=#{cp["id"]}"
        )

      assert body["mode"] == "by_account_cp"
      assert Enum.map(body["rows"], & &1["counterpart_name"]) == [cp["name"]]
      assert hd(body["rows"])["account_number"] == "411"
    end

    test "филтър по сметка 411 — списък с контрагентите ѝ", %{conn: conn, cp: cp} do
      cp2 =
        json_response(
          post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "444555666"}),
          201
        )

      by_number =
        Map.new(
          json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"],
          &{&1["number"], &1["id"]}
        )

      post(conn, "/v1/journal", %{
        "entry_date" => "2026-02-10",
        "document_number" => "J-2",
        "description" => "Покупка",
        "counterpart_id" => cp2["id"],
        "lines" => [
          %{"account_id" => by_number["411"], "direction" => "debit", "amount" => "500.00"},
          %{"account_id" => by_number["401"], "direction" => "credit", "amount" => "500.00"}
        ]
      })

      body = report(conn, "kind=trial_balance&from=2026-01-01&to=2026-12-31&account=411")
      names = Enum.map(body["rows"], & &1["counterpart_name"])
      assert cp["name"] in names
      assert cp2["name"] in names
      assert body["totals"]["turnover_debit"] == "1700.00"
    end
  end

  describe "хронология и главна книга" do
    test "FIFO двойки", %{conn: conn} do
      body = report(conn, "kind=chronological&from=2026-01-01&to=2026-12-31")
      assert length(body["rows"]) == 2
      first = hd(body["rows"])
      assert first["debit_account"] == "411"
      assert first["credit_account"] == "702"
      assert first["debit_amount"] == "1000.00"
      assert Enum.at(body["rows"], 1)["credit_account"] == "4532"
      assert body["totals"]["debit_amount"] == "1200.00"
    end

    test "главна книга с текущо салдо", %{conn: conn} do
      body = report(conn, "kind=general_ledger&from=2026-01-01&to=2026-12-31")
      acc = Enum.find(body["accounts"], &(&1["account_number"] == "411"))
      assert acc["closing_debit"] == "1200.00"
      assert length(acc["transactions"]) == 1
      assert hd(acc["transactions"])["running_debit"] == "1200.00"
    end

    test "кореспонденции — водещ дебит", %{conn: conn} do
      body = report(conn, "kind=correspondence_ledger&from=2026-01-01&to=2026-12-31")
      lead = Enum.find(body["debit_lead"], &(&1["account_number"] == "411"))
      rows = Map.new(lead["rows"], &{&1["correspondent"], &1})
      assert rows["702"]["debit"] == "1000.00"
      assert rows["4532"]["debit"] == "200.00"
    end
  end

  describe "контрагентни справки" do
    test "без избран контрагент — всички, сметката отгоре", %{conn: conn, cp: cp} do
      body = report(conn, "kind=counterpart_trial&from=2026-01-01&to=2026-12-31")
      assert body["mode"] == "by_account_cp"
      assert Enum.all?(body["rows"], &(&1["counterpart_name"] == cp["name"]))

      assert Enum.map(body["rows"], & &1["account_number"]) |> Enum.sort() == [
               "411",
               "4532",
               "702"
             ]

      chrono =
        report(conn, "kind=counterpart_chrono&from=2026-01-01&to=2026-12-31")

      assert Enum.any?(chrono["rows"], &(&1["counterpart_name"] == cp["name"]))
    end

    test "оборотна по контрагент", %{conn: conn, cp: cp} do
      body =
        report(
          conn,
          "kind=counterpart_trial&counterpart_id=#{cp["id"]}&from=2026-01-01&to=2026-12-31"
        )

      rows = Map.new(body["rows"], &{&1["account_number"], &1})
      assert rows["411"]["turnover_debit"] == "1200.00"
    end
  end

  describe "финансови отчети" do
    test "ОПР със стандартни формули", %{conn: conn} do
      defaults =
        json_response(post(conn, "/v1/fs/formulas/defaults", %{"statement" => "pl"}), 200)

      assert defaults["count"] > 0

      body = report(conn, "kind=income_statement&from=2026-01-01&to=2026-12-31")
      assert body["statement"] == "pl"
      rows = Map.new(body["rows"], &{&1["code"], &1})
      assert rows["pl.i.1b"]["current"] == "1000.00"
      assert rows["pl.i.1b"]["prior"] == "0.00"
    end

    test "баланс без формули е нула", %{conn: conn} do
      body = report(conn, "kind=balance_sheet&from=2026-01-01&to=2026-12-31")
      assert body["statement"] == "balance"
      assert Enum.all?(body["rows"], &(&1["current"] == "0.00"))
    end
  end

  describe "формули — fsform" do
    test "каталог и статии", %{conn: conn} do
      list = json_response(get(conn, "/v1/fs/lines"), 200)
      assert list["count"] == 4

      pl = json_response(get(conn, "/v1/fs/lines?statement=pl"), 200)
      assert pl["statement"] == "pl"
      assert Enum.any?(pl["items"], &(&1["code"] == "pl.i.1b"))

      conn = get(conn, "/v1/fs/lines?statement=bogus")
      assert json_response(conn, 400)["detail"] =~ "statement трябва да е"
    end

    test "запис, валидиране и изтриване", %{conn: conn} do
      row =
        json_response(
          put(conn, "/v1/fs/formulas", %{
            "statement" => "pl",
            "line_code" => "pl.i.1b",
            "formula" => "+702ОК"
          }),
          200
        )

      assert row["formula"] == "+702ОК"

      idx = json_response(get(conn, "/v1/fs/formulas?statement=pl"), 200)
      assert idx["count"] == 1

      ok =
        json_response(post(conn, "/v1/fs/formulas/validate", %{"formula" => "+304Д -241К"}), 200)

      assert ok["ok"] == 1
      assert ok["tokens"] == 2

      bad = json_response(post(conn, "/v1/fs/formulas/validate", %{"formula" => "+304"}), 200)
      assert bad["ok"] == 0
      assert bad["error"] != ""

      conn =
        put(conn, "/v1/fs/formulas", %{
          "statement" => "pl",
          "line_code" => "pl.i.1b",
          "formula" => "+304"
        })

      assert json_response(conn, 422)["detail"] != ""

      conn =
        put(conn, "/v1/fs/formulas", %{
          "statement" => "pl",
          "line_code" => "nope",
          "formula" => "+702ОК"
        })

      assert json_response(conn, 422)["detail"] == "непозната статия"

      cleared = json_response(post(conn, "/v1/fs/formulas/clear", %{"statement" => "pl"}), 200)
      assert cleared["count"] == 1
    end

    test "defaults не се презаписват", %{conn: conn} do
      post(conn, "/v1/fs/formulas/defaults", %{"statement" => "balance"})
      conn = post(conn, "/v1/fs/formulas/defaults", %{"statement" => "balance"})
      assert json_response(conn, 422)["detail"] =~ "вече има формули"
    end
  end

  describe "склад и грешки" do
    test "kind=stock връща движения", %{conn: conn} do
      body = report(conn, "kind=stock&from=2026-01-01&to=2026-12-31")
      assert Map.has_key?(body, "receipts")
      assert Map.has_key?(body, "balances")
      assert Map.has_key?(body, "warnings")
    end

    test "липсващи дати и непознат kind", %{conn: conn} do
      conn = get(conn, "/v1/reports?kind=trial_balance")
      assert json_response(conn, 400)["detail"] == "from и to са задължителни (YYYY-MM-DD)"

      conn = get(conn, "/v1/reports?kind=bogus&from=2026-01-01&to=2026-12-31")
      assert json_response(conn, 400)["detail"] == "непознат kind"

      conn = get(conn, "/v1/reports?kind=trial_balance&from=2026-12-31&to=2026-01-01")
      assert json_response(conn, 400)["detail"] == "from трябва да е преди to"
    end

    test "експортът на файлове работи (xlsx), pdf иска sidecar", %{conn: conn} do
      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&format=xlsx&from=2026-01-01&to=2026-12-31"
        )

      assert binary_part(response(conn, 200), 0, 2) == "PK"

      conn =
        get(
          conn,
          "/v1/reports/export?kind=trial_balance&format=pdf&from=2026-01-01&to=2026-12-31"
        )

      assert json_response(conn, 503)["detail"] =~ "sidecar"
    end
  end
end

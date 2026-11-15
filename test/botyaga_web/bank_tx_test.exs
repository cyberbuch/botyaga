defmodule BotyagaWeb.BankTxTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  @csv """
  IBAN: BG93BPBI79401071567501
  Валута: EUR
  Дата;Описание;Контрагент;Дебит;Кредит;Референция
  2026-01-15;ПОС трансакция магазин;Магазин ООД;50.00;;REF-1
  2026-01-16;Получен превод;Клиент АД;;300.00;REF-2
  2026-01-17;Месечна такса за поддръжка;;12.00;;REF-3
  """

  setup do
    {:ok, user} =
      Accounts.create_user("btx@baga.example", "Транзакции", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Транзакции ООД", "eik" => "207123456"}, user)

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    ba =
      json_response(
        post(conn, "/v1/bank-accounts", %{
          "name" => "Основна",
          "iban" => "BG93BPBI79401071567501",
          "gl_account_id" => by_number["501"],
          "buffer_account_id" => by_number["499"]
        }),
        201
      )

    {:ok, conn: conn, company: company, by_number: by_number, ba: ba}
  end

  test "преглед и импорт с автоматичен запис", %{conn: conn, ba: ba} do
    conn =
      post(conn, "/v1/bank-transactions/preview", %{
        "bank_account_id" => ba["id"],
        "file_content" => @csv
      })

    body = json_response(conn, 200)
    assert body["format_name"] == "CSV"
    assert body["total_count"] == 3
    assert body["duplicate_count"] == 0

    conn =
      post(conn, "/v1/bank-transactions/import", %{
        "bank_account_id" => ba["id"],
        "file_content" => @csv
      })

    body = json_response(conn, 200)
    assert body["imported"] == 3
    assert body["journal_count"] == 3

    conn = get(conn, "/v1/bank-transactions?bank_account_id=#{ba["id"]}")
    items = json_response(conn, 200)["items"]
    assert length(items) == 3
    assert Enum.all?(items, & &1["is_booked"])
    assert Enum.find(items, &(&1["reference"] == "REF-1"))["amount"] == "-50.00"

    # повторен импорт пропуска дубликатите
    conn =
      post(conn, "/v1/bank-transactions/import", %{
        "bank_account_id" => ba["id"],
        "file_content" => @csv
      })

    assert json_response(conn, 200)["imported"] == 0
  end

  test "ръчно осчетоводяване и разнасяне", %{conn: conn, ba: ba, by_number: by_number} do
    csv = "Дата;Описание;Дебит;Кредит;Референция\n2026-02-01;Ръчно;100.00;;MAN-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])

    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/reallocate", %{
        "account_id" => by_number["60101"]
      })

    body = json_response(conn, 200)
    assert body["replaced_lines"] == 1

    entry = json_response(get(conn, "/v1/journal/#{tx["journal_entry_id"]}"), 200)
    assert Enum.any?(entry["lines"], &(&1["account_number"] == "60101"))
  end

  test "шаблони и автоматично разнасяне", %{conn: conn, ba: ba, by_number: by_number} do
    # банка без буфер → транзакциите остават нови за ръчно/авто разнасяне
    ba2 =
      json_response(
        post(conn, "/v1/bank-accounts", %{
          "name" => "Без буфер",
          "iban" => "BG11111111111111111111",
          "gl_account_id" => by_number["501"]
        }),
        201
      )

    conn = post(conn, "/v1/bank-matching-rules/defaults", %{})
    assert json_response(conn, 200)["created"] > 0

    csv =
      "Дата;Описание;Контрагент;Дебит;Кредит;Референция\n2026-03-01;ПОС трансакция;Магазин;25.00;;A-1\n2026-03-02;месечна такса;;5.00;;A-2\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba2["id"],
      "file_content" => csv
    })

    conn = post(conn, "/v1/bank-transactions/auto-allocate/preview", %{})
    body = json_response(conn, 200)
    assert body["matched"] == 2

    conn = post(conn, "/v1/bank-transactions/auto-allocate", %{})
    body = json_response(conn, 200)
    assert body["matched"] == 2
    assert body["errors"] == 0

    items = json_response(get(conn, "/v1/bank-transactions?status=allocated"), 200)["items"]
    assert length(items) == 2
    _ = ba
  end

  test "триене на транзакция трие и статията", %{conn: conn, ba: ba} do
    csv = "Дата;Описание;Дебит;Кредит;Референция\n2026-04-01;За триене;10.00;;DEL-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])

    conn = delete(conn, "/v1/bank-transactions/#{tx["id"]}")
    assert response(conn, 204)

    conn = get(conn, "/v1/journal/#{tx["journal_entry_id"]}")
    assert json_response(conn, 404)
  end
end

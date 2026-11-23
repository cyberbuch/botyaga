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

  test "преглед и импорт без автоматичен запис", %{conn: conn, ba: ba} do
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
    assert body["journal_count"] == 0

    conn = get(conn, "/v1/bank-transactions?bank_account_id=#{ba["id"]}")
    items = json_response(conn, 200)["items"]
    assert length(items) == 3
    assert Enum.all?(items, &(not &1["is_booked"]))
    assert Enum.all?(items, &(&1["journal_entry_id"] in [nil, 0]))
    assert Enum.find(items, &(&1["reference"] == "REF-1"))["amount"] == "-50.00"

    # повторен импорт пропуска дубликатите
    conn =
      post(conn, "/v1/bank-transactions/import", %{
        "bank_account_id" => ba["id"],
        "file_content" => @csv
      })

    assert json_response(conn, 200)["imported"] == 0
  end

  test "осчетоводяването изисква преглед и потвърждение", %{
    conn: conn,
    ba: ba,
    by_number: by_number
  } do
    csv =
      "Дата;Описание;Контрагент;Дебит;Кредит;Референция\n2026-02-01;Плащане към доставчик;Доставчик ООД;100.00;;MAN-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert tx["is_booked"] == false

    # без confirm → 422, нищо не се записва
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "contra_account_id" => by_number["401"]
      })

    assert json_response(conn, 422)

    still_new =
      hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])

    assert still_new["is_booked"] == false

    # preview връща предложения запис (Дт/Кт), без да създава статия
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book/preview", %{
        "contra_account_id" => by_number["401"]
      })

    preview = json_response(conn, 200)
    assert preview["requires_confirm"] == true
    assert preview["amount"] == "100.00"
    assert length(preview["lines"]) == 2

    debit_line = Enum.find(preview["lines"], &(&1["direction"] == "debit"))
    credit_line = Enum.find(preview["lines"], &(&1["direction"] == "credit"))
    assert debit_line["account_number"] == "401"
    assert credit_line["account_number"] == "501"

    still_new = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert still_new["is_booked"] == false

    # с confirm=true транзакцията се осчетоводява
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "contra_account_id" => by_number["401"],
        "confirm" => true
      })

    body = json_response(conn, 200)
    entry_id = body["journal_entry_id"]
    assert is_integer(entry_id)

    booked = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert booked["is_booked"] == true
    assert booked["is_allocated"] == true
    assert booked["journal_entry_id"] == entry_id

    entry = json_response(get(conn, "/v1/journal/#{entry_id}"), 200)
    assert Enum.any?(entry["lines"], &(&1["account_number"] == "401"))
    assert Enum.any?(entry["lines"], &(&1["account_number"] == "501"))

    # повторно осчетоводяване → 409
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "contra_account_id" => by_number["401"],
        "confirm" => true
      })

    assert json_response(conn, 409)
  end

  test "шаблони и автоматично разнасяне", %{conn: conn, by_number: by_number} do
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

    # груповото обработване е само преглед — НЕ осчетоводява автоматично
    conn = post(conn, "/v1/bank-transactions/auto-allocate", %{})
    body = json_response(conn, 200)
    assert body["matched"] == 2
    assert json_response(get(conn, "/v1/bank-transactions?status=allocated"), 200)["items"] == []

    # осчетоводяването е поединично, с потвърждение и избрана насрещна сметка
    tx = hd(json_response(get(conn, "/v1/bank-transactions?status=new"), 200)["items"])

    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "confirm" => true,
        "contra_account_id" => by_number["60201"]
      })

    assert response(conn, 200)

    items = json_response(get(conn, "/v1/bank-transactions?status=allocated"), 200)["items"]
    assert length(items) == 1
  end

  test "осчетоводяване с редове (валутна операция с комисионна) и връщане в чернова", %{
    conn: conn,
    ba: ba,
    by_number: by_number
  } do
    # EUR сметка получава 1000 EUR от превод от USD сметка: 1100 USD по курс
    # 0.92 = 1012 EUR, от които 12 EUR е банкова комисионна (разход).
    csv =
      "Дата;Описание;Контрагент;Дебит;Кредит;Референция\n2026-05-01;Превод от USD сметка;Банка ООД;;1000.00;FX-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])

    lines = [
      %{"account_id" => by_number["501"], "direction" => "debit", "amount" => "1000.00"},
      %{
        "account_id" => by_number["401"],
        "direction" => "credit",
        "amount" => "1012.00",
        "currency" => "USD",
        "fx_quantity" => "1100.00",
        "fx_rate" => "0.92"
      },
      %{"account_id" => by_number["629"], "direction" => "debit", "amount" => "12.00"}
    ]

    # preview с редове — балансиран, без запис в базата
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book/preview", %{
        "lines" => lines,
        "entry_date" => "2026-05-01",
        "description" => "Превод USD→EUR"
      })

    preview = json_response(conn, 200)
    assert preview["requires_confirm"] == true
    assert preview["balanced"] == true
    assert preview["debit_total"] == "1012.00"
    assert preview["credit_total"] == "1012.00"
    assert length(preview["lines"]) == 3

    usd_line = Enum.find(preview["lines"], &(&1["currency"] == "USD"))
    assert usd_line["fx_quantity"] == "1100.00"
    assert usd_line["fx_rate"] == "0.92"
    assert usd_line["amount"] == "1012.00"

    still_new = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert still_new["is_booked"] == false

    # небалансиран запис → 422
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "confirm" => true,
        "lines" => [hd(lines)]
      })

    assert json_response(conn, 422)

    # запис без банковата ГЛ сметка → 422
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "confirm" => true,
        "lines" => [
          %{"account_id" => by_number["401"], "direction" => "debit", "amount" => "1000.00"},
          %{"account_id" => by_number["629"], "direction" => "credit", "amount" => "1000.00"}
        ]
      })

    assert json_response(conn, 422)

    # без confirm → 422
    conn = post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{"lines" => lines})
    assert json_response(conn, 422)

    # с confirm=true транзакцията се осчетоводява с 3 реда и валутни полета
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "confirm" => true,
        "lines" => lines,
        "entry_date" => "2026-05-01",
        "description" => "Превод USD→EUR"
      })

    body = json_response(conn, 200)
    entry_id = body["journal_entry_id"]
    assert is_integer(entry_id)

    booked = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert booked["is_booked"] == true
    assert booked["is_allocated"] == true
    assert booked["journal_entry_id"] == entry_id

    entry = json_response(get(conn, "/v1/journal/#{entry_id}"), 200)
    assert entry["document_type"] == "bank"
    assert entry["description"] == "Превод USD→EUR"
    assert length(entry["lines"]) == 3

    usd = Enum.find(entry["lines"], &(&1["currency"] == "USD"))
    assert usd["account_number"] == "401"
    assert usd["fx_quantity"] == "1100.00"
    assert usd["fx_rate"] == "0.92"
    assert usd["amount"] == "1012.00"

    # връщане в чернова → статията се трие, флаговете се нулират
    conn = post(conn, "/v1/bank-transactions/#{tx["id"]}/unbook", %{})
    assert json_response(conn, 200)["message"] =~ "чернова"

    draft = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    assert draft["is_booked"] == false
    assert draft["is_allocated"] == false
    assert draft["journal_entry_id"] in [nil, 0]

    conn = get(conn, "/v1/journal/#{entry_id}")
    assert json_response(conn, 404)

    # повторно осчетоводяване след връщане в чернова — отново позволено
    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "confirm" => true,
        "contra_account_id" => by_number["401"]
      })

    assert json_response(conn, 200)["journal_entry_id"] > 0
  end

  test "unbook на неосчетоводена транзакция → 409", %{conn: conn, ba: ba} do
    csv = "Дата;Описание;Дебит;Кредит;Референция\n2026-06-01;Нова;10.00;;U-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])
    conn = post(conn, "/v1/bank-transactions/#{tx["id"]}/unbook", %{})
    assert json_response(conn, 409)
  end

  test "триене на транзакция трие и статията", %{conn: conn, ba: ba, by_number: by_number} do
    csv = "Дата;Описание;Дебит;Кредит;Референция\n2026-04-01;За триене;10.00;;DEL-1\n"

    post(conn, "/v1/bank-transactions/import", %{
      "bank_account_id" => ba["id"],
      "file_content" => csv
    })

    tx = hd(json_response(get(conn, "/v1/bank-transactions"), 200)["items"])

    conn =
      post(conn, "/v1/bank-transactions/#{tx["id"]}/book", %{
        "contra_account_id" => by_number["629"],
        "confirm" => true
      })

    entry_id = json_response(conn, 200)["journal_entry_id"]

    conn = delete(conn, "/v1/bank-transactions/#{tx["id"]}")
    assert response(conn, 204)

    conn = get(conn, "/v1/journal/#{entry_id}")
    assert json_response(conn, 404)
  end
end

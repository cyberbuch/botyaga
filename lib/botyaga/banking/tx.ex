defmodule Botyaga.Banking.Tx do
  @moduledoc """
  Банкови транзакции: преглед, импорт, ръчно осчетоводяване и разнасяне.

  Импортът НЕ създава счетоводни записи — транзакциите остават „нови“.
  Всяка транзакция се осчетоводява само след изрично потвърждение:
  `book_preview` връща предложения запис (Дт/Кт) без да пише в базата,
  а `book` изисква `confirm=true` и едва тогава създава статията.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Journal, Params, Periods, Rates, Repo}
  alias Botyaga.Banking.{Account, Formats, Transaction}

  @unknown "Непознат формат на файла. Поддържаните формати са: OBB XML, ISO camt.053, PostBank XML, MT-940, CSV."

  def index(company_id, params) do
    account_id = Params.id(params["bank_account_id"] || 0)

    query =
      if account_id > 0 do
        from(t in Transaction,
          where: t.company_id == ^company_id and t.bank_account_id == ^account_id,
          order_by: [asc: t.id]
        )
      else
        from(t in Transaction, where: t.company_id == ^company_id, order_by: [asc: t.id])
      end

    status = params["status"] || ""

    names =
      Repo.all(from(a in Account, where: a.company_id == ^company_id, select: {a.id, a.name}))
      |> Map.new()

    Repo.all(query)
    |> Enum.filter(fn t -> keep?(t, status) end)
    |> Enum.map(&tx_json(&1, Map.get(names, &1.bank_account_id)))
  end

  defp keep?(t, "new"), do: t.is_booked == 0
  defp keep?(t, "booked"), do: t.is_booked != 0 and t.is_allocated == 0
  defp keep?(t, "allocated"), do: t.is_allocated != 0
  defp keep?(_, _), do: true

  def preview(company_id, params) do
    with {:ok, ba_id} <- req_id(params, "bank_account_id"),
         {:ok, content} <- required(params, "file_content"),
         {:ok, ba} <- bank(company_id, ba_id),
         {:ok, parsed} <- detect(content, ba.statement_format) do
      refs = refs_of(ba_id)
      {txs, dup} = mark_duplicates(parsed.txs, refs)
      {:ok, pack(parsed, txs, dup)}
    end
  end

  def import(company_id, _sub, params) do
    with {:ok, ba_id} <- req_id(params, "bank_account_id"),
         {:ok, content} <- required(params, "file_content"),
         {:ok, ba} <- bank(company_id, ba_id),
         {:ok, parsed} <- detect(content, ba.statement_format) do
      refs = refs_of(ba_id)

      result =
        Repo.transaction(fn ->
          Enum.reduce(parsed.txs, 0, fn tx, imported ->
            if tx.reference != "" and tx.reference in refs do
              imported
            else
              case Dec.parse(tx.amount) do
                nil ->
                  imported

                amount ->
                  tx_type = if amount < 0, do: "WITHDRAWAL", else: "DEPOSIT"
                  currency = if tx.currency == "", do: ba.currency, else: tx.currency

                  Repo.insert!(%Transaction{
                    company_id: company_id,
                    bank_account_id: ba_id,
                    txn_date: tx.date,
                    amount: Dec.money(amount),
                    currency: currency,
                    counterpart_name: tx.contra_name,
                    counterpart_iban: tx.contra_iban,
                    description: tx.description,
                    reference: tx.reference,
                    transaction_type: tx_type,
                    is_booked: 0,
                    is_allocated: 0
                  })

                  imported + 1
              end
            end
          end)
        end)

      case result do
        {:ok, imported} ->
          {:ok, %{imported: imported, journal_count: 0}}

        {:error, reason} ->
          {:error, {500, inspect(reason)}}
      end
    end
  end

  def book(company_id, sub, id, params) do
    with :ok <- confirmed(params) do
      if lines_given?(params) do
        book_lines(company_id, sub, id, params)
      else
        cp = Params.integer(params, "counterpart_id") || 0
        contra = Params.integer(params, "contra_account_id") || 0
        debit = Params.integer(params, "debit_account_id")
        credit = Params.integer(params, "credit_account_id")
        book_tx(company_id, sub, id, contra, cp, debit, credit)
      end
    end
  end

  @doc """
  Връща осчетоводена транзакция в чернова: статията се изтрива, флаговете се
  нулират. Само в чернова банковите транзакции могат да се редактират (пре-
  осчетоводяват) отново.
  """
  def unbook(company_id, sub, id) do
    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- booked(tx),
         :ok <- Periods.assert_open(company_id, tx.txn_date) do
      entry_id = tx.journal_entry_id

      if entry_id > 0 do
        Journal.wipe(entry_id)

        Audit.record(
          company_id,
          sub,
          "journal",
          entry_id,
          tx.reference,
          "delete",
          "Изтрита статия #{entry_id} — банкова транзакция #{tx.id} (#{tx.reference}) е върната в чернова, сума #{tx.amount}",
          tx.amount,
          "",
          nil,
          nil
        )
      end

      Repo.update!(Ecto.Changeset.change(tx, is_booked: 0, is_allocated: 0, journal_entry_id: 0))

      Audit.record(
        company_id,
        sub,
        "bank_tx",
        tx.id,
        tx.reference,
        "update",
        "Банкова транзакция #{tx.id} (#{tx.reference}) върната в чернова за редактиране, сума #{tx.amount} #{tx.currency}",
        tx.amount,
        tx.amount,
        nil,
        nil
      )

      {:ok, %{message: "транзакцията е върната в чернова", transaction_id: tx.id}}
    end
  end

  defp confirmed(params) do
    case Params.flag(params, "confirm") do
      1 ->
        :ok

      _ ->
        {:error, {422, "Осчетоводяването изисква потвърждение: confirm=true"}}
    end
  end

  def book_preview(company_id, id, params) do
    if lines_given?(params) do
      lines_preview(company_id, id, params)
    else
      simple_preview(company_id, id, params)
    end
  end

  defp simple_preview(company_id, id, params) do
    cp = Params.integer(params, "counterpart_id") || 0
    contra = Params.integer(params, "contra_account_id") || 0
    debit = Params.integer(params, "debit_account_id")
    credit = Params.integer(params, "credit_account_id")

    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- ensure_ref(Catalog.Account, contra, company_id, "сметката"),
         :ok <- not_booked(tx),
         {:ok, amount} <- tx_amount(tx),
         {:ok, ba} <- bank(company_id, tx.bank_account_id),
         {:ok, debit_id, credit_id} <- sides(ba, contra, debit, credit, amount, company_id),
         :ok <- Periods.assert_open(company_id, tx.txn_date),
         {:ok, debit_acc} <- account_by_id(debit_id, company_id),
         {:ok, credit_acc} <- account_by_id(credit_id, company_id) do
      abs_s = Dec.money(Dec.abs(amount))

      {:ok,
       %{
         transaction_id: tx.id,
         date: tx.txn_date,
         amount: abs_s,
         currency: tx.currency,
         description: base_desc(tx),
         requires_confirm: true,
         lines: [
           %{
             account_id: debit_acc.id,
             account_number: debit_acc.number,
             account_name: debit_acc.name,
             direction: "debit",
             amount: abs_s
           },
           %{
             account_id: credit_acc.id,
             account_number: credit_acc.number,
             account_name: credit_acc.name,
             direction: "credit",
             amount: abs_s
           }
         ]
       }}
    end
  end

  def book_tx(company_id, sub, id, contra, cp, debit_opt, credit_opt) do
    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- ensure_ref(Catalog.Account, contra, company_id, "сметката"),
         :ok <- not_booked(tx),
         {:ok, amount} <- tx_amount(tx),
         {:ok, ba} <- bank(company_id, tx.bank_account_id),
         {:ok, debit_id, credit_id} <-
           sides(ba, contra, debit_opt, credit_opt, amount, company_id),
         {:ok, cp_name} <- counterpart_name(cp, company_id),
         :ok <- Periods.assert_open(company_id, tx.txn_date),
         {:ok, debit} <- account_by_id(debit_id, company_id),
         {:ok, credit} <- account_by_id(credit_id, company_id) do
      abs_s = Dec.money(Dec.abs(amount))
      shown = if cp > 0, do: cp_name, else: tx.counterpart_name
      desc = base_desc(tx)

      {:ok, entry} =
        Journal.write_entry(
          company_id,
          tx.txn_date,
          "bank",
          0,
          tx.reference,
          desc,
          cp,
          shown,
          month_of(tx.txn_date),
          [
            %{account: debit, direction: "debit", amount: abs_s},
            %{account: credit, direction: "credit", amount: abs_s}
          ]
        )

      Repo.update!(
        Ecto.Changeset.change(tx, is_booked: 1, is_allocated: 1, journal_entry_id: entry)
      )

      apply_fx(entry, tx, company_id, abs_s)

      Audit.record(
        company_id,
        sub,
        "journal",
        entry,
        tx.reference,
        "create",
        "Осчетоводена банкова транзакция #{tx.id} (#{tx.reference}) — #{shown}, Дт #{debit.number} / Кт #{credit.number}, сума #{abs_s}",
        "",
        abs_s,
        nil,
        nil
      )

      result = %{message: "транзакцията е осчетоводена", journal_entry_id: entry}
      {:ok, if(cp > 0, do: Map.put(result, :counterpart_id, cp), else: result)}
    end
  end

  # Ръчно осчетоводяване с произволни редове (като „Нов запис“ в дневника):
  # валута по ред, курс, количество — напр. превод USD→EUR по курс ЕЦБ с
  # отделен ред за банковата комисионна.
  defp book_lines(company_id, sub, id, params) do
    cp = Params.integer(params, "counterpart_id") || 0

    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- not_booked(tx),
         :ok <- ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         {:ok, ba} <- bank(company_id, tx.bank_account_id),
         {:ok, date} <- entry_date(params, tx),
         :ok <- Periods.assert_open(company_id, date),
         {:ok, lines} <- parse_lines(params, company_id),
         :ok <- check_balanced(lines),
         :ok <- ensure_bank_line(lines, ba),
         {:ok, cp_name} <- counterpart_name(cp, company_id) do
      desc = param_desc(params, tx)
      shown = if cp > 0, do: cp_name, else: tx.counterpart_name

      sides =
        Enum.map(lines, fn l ->
          %{
            account: l.account,
            direction: l.direction,
            amount: l.amount,
            currency: l.currency,
            fx_quantity: l.fx_quantity,
            fx_rate: l.fx_rate
          }
        end)

      {:ok, entry} =
        Journal.write_entry(
          company_id,
          date,
          "bank",
          0,
          tx.reference,
          desc,
          cp,
          shown,
          month_of(date),
          sides
        )

      Repo.update!(
        Ecto.Changeset.change(tx, is_booked: 1, is_allocated: 1, journal_entry_id: entry)
      )

      {debit, _credit} = line_totals(lines)

      Audit.record(
        company_id,
        sub,
        "journal",
        entry,
        tx.reference,
        "create",
        "Осчетоводена банкова транзакция #{tx.id} (#{tx.reference}) — #{shown}, #{length(lines)} реда, оборот #{Dec.money(debit)}",
        "",
        Dec.money(debit),
        nil,
        nil
      )

      result = %{message: "транзакцията е осчетоводена", journal_entry_id: entry}
      {:ok, if(cp > 0, do: Map.put(result, :counterpart_id, cp), else: result)}
    end
  end

  def reallocate(company_id, sub, id, params) do
    with {:ok, new_acc} <- req_id(params, "account_id") do
      cp = Params.integer(params, "counterpart_id") || 0
      reallocate_tx(company_id, sub, id, new_acc, cp)
    end
  end

  def reallocate_tx(company_id, sub, id, new_acc, cp) do
    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- ensure_ref(Catalog.Account, new_acc, company_id, "сметката"),
         :ok <- ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- has_entry(tx),
         {:ok, ba} <- bank(company_id, tx.bank_account_id),
         :ok <- has_buffer(ba),
         {:ok, cp_name} <- counterpart_name(cp, company_id),
         {:ok, acct} <- account_by_id(new_acc, company_id) do
      lines = Repo.all(from(l in Journal.Line, where: l.entry_id == ^tx.journal_entry_id))
      buffer_lines = Enum.filter(lines, &(&1.account_id == ba.buffer_account_id))

      if buffer_lines == [] do
        {:error, {422, "Не е намерен ред с буферна сметка"}}
      else
        Enum.each(buffer_lines, fn line ->
          Repo.update!(
            Ecto.Changeset.change(line,
              account_id: acct.id,
              account_number: acct.number,
              account_name: acct.name
            )
          )
        end)

        if cp > 0 do
          Repo.update_all(from(e in Journal.Entry, where: e.id == ^tx.journal_entry_id),
            set: [counterpart_id: cp, counterpart_name: cp_name]
          )
        end

        Repo.update!(Ecto.Changeset.change(tx, is_allocated: 1))
        acc_name = if acct.name in [nil, ""], do: acct.number, else: "#{acct.number} #{acct.name}"

        Audit.record(
          company_id,
          sub,
          "journal",
          tx.journal_entry_id,
          tx.reference,
          "update",
          "Разнесена банкова транзакция #{tx.id} (#{tx.reference}) към сметка #{acc_name} (#{cp_name}), сума #{tx.amount}",
          tx.amount,
          tx.amount,
          nil,
          nil
        )

        {:ok,
         %{
           message: "Транзакцията е разнесена към #{acc_name}",
           account_name: acc_name,
           replaced_lines: length(buffer_lines)
         }}
      end
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, tx} <- tx_row(company_id, id) do
      if tx.journal_entry_id > 0 do
        Journal.wipe(tx.journal_entry_id)

        Audit.record(
          company_id,
          sub,
          "journal",
          tx.journal_entry_id,
          tx.reference,
          "delete",
          "Изтрита банкова транзакция #{tx.id} (#{tx.reference}) и статия #{tx.journal_entry_id}, сума #{tx.amount}",
          tx.amount,
          "",
          nil,
          nil
        )
      end

      Repo.delete!(tx)
      {:ok, nil}
    end
  end

  def bulk_delete(company_id, sub, ids) do
    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {deleted, failed} ->
        case delete(company_id, sub, id) do
          {:ok, nil} -> {deleted + 1, failed}
          _ -> {deleted, failed + 1}
        end
      end)

    %{deleted: deleted, failed: failed}
  end

  ## Вътрешни

  defp lines_given?(params) do
    case Map.get(params, "lines") do
      arr when is_list(arr) -> arr != []
      _ -> false
    end
  end

  defp lines_preview(company_id, id, params) do
    cp = Params.integer(params, "counterpart_id") || 0

    with {:ok, tx} <- tx_row(company_id, id),
         :ok <- not_booked(tx),
         :ok <- ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         {:ok, ba} <- bank(company_id, tx.bank_account_id),
         {:ok, date} <- entry_date(params, tx),
         :ok <- Periods.assert_open(company_id, date),
         {:ok, lines} <- parse_lines(params, company_id),
         :ok <- ensure_bank_line(lines, ba) do
      {debit, credit} = line_totals(lines)
      amount = tx_amount(tx)

      {:ok,
       %{
         transaction_id: tx.id,
         date: date,
         amount:
           case amount do
             {:ok, a} -> Dec.money(Dec.abs(a))
             _ -> tx.amount
           end,
         currency: tx.currency,
         description: param_desc(params, tx),
         requires_confirm: true,
         balanced: debit == credit,
         debit_total: Dec.money(debit),
         credit_total: Dec.money(credit),
         lines: Enum.map(lines, &line_json/1)
       }}
    end
  end

  defp entry_date(params, tx) do
    case Params.str(params, "entry_date") do
      {:present, v} ->
        v = String.trim(v)

        cond do
          v == "" -> {:ok, tx.txn_date}
          String.match?(v, ~r/^\d{4}-\d{2}-\d{2}$/) -> {:ok, v}
          true -> {:error, {422, "entry_date трябва да е във формат YYYY-MM-DD"}}
        end

      _ ->
        {:ok, tx.txn_date}
    end
  end

  defp param_desc(params, tx) do
    case Params.str(params, "description") do
      {:present, v} ->
        v = String.trim(v)
        if v == "", do: base_desc(tx), else: v

      _ ->
        base_desc(tx)
    end
  end

  defp parse_lines(params, company_id) do
    case Map.get(params, "lines") do
      arr when is_list(arr) and arr != [] -> parse_each(arr, 0, [], company_id)
      _ -> {:error, {422, "lines е задължително и не може да е празен"}}
    end
  end

  defp parse_each([], _index, acc, _company_id), do: {:ok, Enum.reverse(acc)}

  defp parse_each([item | rest], index, acc, company_id) when is_map(item) do
    account_id = Params.integer(item, "account_id") || 0
    direction = item |> line_str("direction") |> String.trim()
    amount = item |> line_str("amount") |> String.trim()
    currency = item |> line_str("currency") |> String.trim() |> String.upcase()
    fx_quantity = item |> line_str("fx_quantity") |> String.trim()
    fx_rate = item |> line_str("fx_rate") |> String.trim()

    cond do
      account_id <= 0 ->
        {:error, {422, "lines[#{index}].account_id е задължителен"}}

      direction not in ["debit", "credit"] ->
        {:error, {422, "lines[#{index}].direction трябва да е debit или credit"}}

      true ->
        case Dec.parse(amount) do
          nil ->
            {:error, {422, "lines[#{index}].amount е невалидна сума"}}

          0 ->
            {:error, {422, "lines[#{index}].amount не може да е 0"}}

          cents ->
            case Repo.get_by(Catalog.Account, id: account_id, company_id: company_id) do
              nil ->
                {:error, {404, "lines[#{index}]: сметката не е намерена"}}

              account ->
                line = %{
                  account_id: account_id,
                  account: account,
                  direction: direction,
                  amount: Dec.money(cents),
                  cents: cents,
                  currency: currency,
                  fx_quantity: if(fx_quantity == "", do: Dec.money(cents), else: fx_quantity),
                  fx_rate: if(fx_rate == "", do: "1", else: fx_rate)
                }

                parse_each(rest, index + 1, [line | acc], company_id)
            end
        end
    end
  end

  defp parse_each(_, index, _acc, _company_id),
    do: {:error, {422, "lines[#{index}] трябва да е обект"}}

  defp line_str(item, key) do
    case Params.str(item, key) do
      {:present, v} -> v
      _ -> ""
    end
  end

  defp line_totals(lines) do
    Enum.reduce(lines, {0, 0}, fn l, {d, c} ->
      if l.direction == "debit", do: {d + l.cents, c}, else: {d, c + l.cents}
    end)
  end

  defp check_balanced(lines) do
    {debit, credit} = line_totals(lines)

    if debit == credit do
      :ok
    else
      {:error, {422, "записът не е балансиран: Дт=#{Dec.money(debit)} Кт=#{Dec.money(credit)}"}}
    end
  end

  # Когато банковата сметка има свързана ГЛ сметка, записът задължително
  # трябва да я съдържа — иначе банковото движение не се отразява.
  defp ensure_bank_line(lines, %Account{gl_account_id: gl}) when gl > 0 do
    if Enum.any?(lines, &(&1.account_id == gl)) do
      :ok
    else
      {:error, {422, "записът трябва да съдържа банковата ГЛ сметка на транзакцията"}}
    end
  end

  defp ensure_bank_line(_lines, _ba), do: :ok

  defp line_json(l) do
    %{
      account_id: l.account_id,
      account_number: l.account.number,
      account_name: l.account.name,
      direction: l.direction,
      amount: l.amount,
      currency: l.currency,
      fx_quantity: l.fx_quantity,
      fx_rate: l.fx_rate
    }
  end

  defp booked(%Transaction{is_booked: v}) when v != 0, do: :ok
  defp booked(_), do: {:error, {409, "транзакцията не е осчетоводена"}}

  defp detect(content, hint) do
    case Formats.detect(content, hint) do
      nil -> {:error, {422, @unknown}}
      parsed -> {:ok, parsed}
    end
  end

  defp mark_duplicates(txs, refs) do
    {txs, dup} =
      Enum.map_reduce(txs, 0, fn tx, dup ->
        if tx.reference != "" and tx.reference in refs do
          {%{tx | is_duplicate: true}, dup + 1}
        else
          {tx, dup}
        end
      end)

    {txs, dup}
  end

  defp pack(parsed, txs, dup) do
    total = length(txs)

    %{
      format_name: parsed.format_name,
      account_iban: parsed.account_iban,
      account_currency: parsed.account_currency,
      transactions:
        Enum.map(txs, fn tx ->
          %{
            date: tx.date,
            amount: tx.amount,
            currency: tx.currency,
            description: tx.description,
            contra_name: tx.contra_name,
            contra_iban: tx.contra_iban,
            reference: tx.reference,
            is_duplicate: tx.is_duplicate
          }
        end),
      total_count: total,
      duplicate_count: dup,
      new_count: total - dup
    }
  end

  defp refs_of(ba_id) do
    Repo.all(from(t in Transaction, where: t.bank_account_id == ^ba_id, select: t.reference))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp bank(company_id, id) do
    case Repo.get_by(Account, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "Банковата сметка не е намерена"}}
      account -> {:ok, account}
    end
  end

  defp tx_row(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Transaction, id: id, company_id: company_id) do
        nil -> {:error, {404, "Транзакцията не е намерена"}}
        tx -> {:ok, tx}
      end
    end
  end

  defp not_booked(%Transaction{is_booked: 0}), do: :ok
  defp not_booked(_), do: {:error, {409, "транзакцията вече е осчетоводена"}}

  defp tx_amount(tx) do
    case Dec.parse(tx.amount) do
      nil -> {:error, {422, "невалидна сума на транзакцията"}}
      amount -> {:ok, amount}
    end
  end

  defp sides(ba, contra, debit_opt, credit_opt, amount, company_id) do
    if contra > 0 do
      if ba.gl_account_id <= 0 do
        {:error, {422, "Банковата сметка няма свързана GL сметка"}}
      else
        if amount >= 0, do: {:ok, ba.gl_account_id, contra}, else: {:ok, contra, ba.gl_account_id}
      end
    else
      cond do
        is_nil(debit_opt) ->
          {:error, {422, "debit_account_id е задължително"}}

        is_nil(credit_opt) ->
          {:error, {422, "credit_account_id е задължително"}}

        debit_opt <= 0 or credit_opt <= 0 ->
          {:error, {422, "debit_account_id е задължително"}}

        true ->
          with :ok <- ensure_ref(Catalog.Account, debit_opt, company_id, "сметката"),
               :ok <- ensure_ref(Catalog.Account, credit_opt, company_id, "сметката") do
            {:ok, debit_opt, credit_opt}
          end
      end
    end
  end

  defp has_entry(%Transaction{journal_entry_id: entry}) when entry > 0, do: :ok
  defp has_entry(_), do: {:error, {422, "Транзакцията няма счетоводен запис"}}

  defp has_buffer(%Account{buffer_account_id: buf}) when buf > 0, do: :ok
  defp has_buffer(_), do: {:error, {422, "Няма буферна сметка"}}

  defp counterpart_name(cp, _company_id) when cp <= 0, do: {:ok, ""}

  defp counterpart_name(cp, company_id) do
    case Repo.get_by(Catalog.Counterpart, id: cp, company_id: company_id) do
      nil -> {:error, {404, "Контрагентът не е намерен"}}
      counterpart -> {:ok, counterpart.name}
    end
  end

  defp account_by_id(id, company_id) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company_id) do
      nil -> {:error, {422, "липсва сметка с id #{id}"}}
      account -> {:ok, account}
    end
  end

  defp ensure_ref(_schema, id, _company_id, _what) when id <= 0, do: :ok

  defp ensure_ref(schema, id, company_id, what) do
    if Repo.get_by(schema, id: id, company_id: company_id) == nil do
      {:error, {404, "#{what} не е намерен"}}
    else
      :ok
    end
  end

  defp base_desc(tx) do
    desc = if tx.description in [nil, ""], do: "Ръчно осчетоводяване", else: tx.description
    if tx.counterpart_name in [nil, ""], do: desc, else: "#{desc} - #{tx.counterpart_name}"
  end

  defp apply_fx(entry, tx, company_id, abs_s) do
    tx_cur = tx.currency |> to_string() |> String.trim() |> String.upcase()
    base = base_currency(company_id)

    {cur, rate} =
      if tx_cur in ["", base] do
        {"", "1"}
      else
        case Rates.cross_rate(tx_cur, base, tx.txn_date) do
          {:ok, {r, _}} -> {tx_cur, r}
          {:error, _} -> {"", "1"}
        end
      end

    Repo.update_all(from(l in Journal.Line, where: l.entry_id == ^entry),
      set: [currency: cur, fx_quantity: abs_s, fx_rate: rate]
    )
  end

  defp base_currency(company_id) do
    case Companies.get_company(company_id) do
      nil ->
        "EUR"

      company ->
        case String.trim(company.currency || "") |> String.upcase() do
          "" -> "EUR"
          currency -> currency
        end
    end
  end

  defp month_of(date), do: if(String.length(date) >= 7, do: String.slice(date, 0, 7), else: date)

  defp tx_json(t, ba_name) do
    %{
      id: t.id,
      bank_account_id: t.bank_account_id,
      bank_account_name: ba_name || "",
      transaction_date: t.txn_date,
      amount: t.amount,
      currency: t.currency,
      counterpart_name: t.counterpart_name,
      counterpart_iban: t.counterpart_iban,
      description: t.description,
      reference: t.reference,
      transaction_type: t.transaction_type,
      is_booked: t.is_booked != 0,
      is_allocated: t.is_allocated != 0,
      journal_entry_id: t.journal_entry_id,
      company_id: t.company_id
    }
  end

  defp req_id(params, key) do
    case Params.integer(params, key) do
      nil -> {:error, {422, "#{key} е задължително"}}
      {:error, _} -> {:error, {422, "#{key} е задължително"}}
      value when value <= 0 -> {:error, {422, "#{key} е задължително"}}
      value -> {:ok, value}
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end
end

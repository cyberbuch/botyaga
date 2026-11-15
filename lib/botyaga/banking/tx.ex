defmodule Botyaga.Banking.Tx do
  @moduledoc """
  Банкови транзакции: преглед, импорт, ръчно осчетоводяване и разнасяне.
  Автоматичният запис е Дт ГЛ / Кт буфер при плюс и обратно при минус.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Companies, Dec, Journal, Params, Periods, Rates, Repo}
  alias Botyaga.Banking.{Account, Csv, Transaction}

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

    Repo.all(query)
    |> Enum.filter(fn t -> keep?(t, status) end)
    |> Enum.map(&tx_json/1)
  end

  defp keep?(t, "new"), do: t.is_booked == 0
  defp keep?(t, "booked"), do: t.is_booked != 0 and t.is_allocated == 0
  defp keep?(t, "allocated"), do: t.is_allocated != 0
  defp keep?(_, _), do: true

  def preview(company_id, params) do
    with {:ok, ba_id} <- req_id(params, "bank_account_id"),
         {:ok, content} <- required(params, "file_content"),
         {:ok, _ba} <- bank(company_id, ba_id),
         {:ok, parsed} <- detect(content) do
      refs = refs_of(ba_id)
      {txs, dup} = mark_duplicates(parsed.txs, refs)
      {:ok, pack(parsed, txs, dup)}
    end
  end

  def import(company_id, sub, params) do
    with {:ok, ba_id} <- req_id(params, "bank_account_id"),
         {:ok, content} <- required(params, "file_content"),
         {:ok, ba} <- bank(company_id, ba_id),
         {:ok, parsed} <- detect(content) do
      refs = refs_of(ba_id)
      auto = ba.gl_account_id > 0 and ba.buffer_account_id > 0

      with :ok <- check_periods(company_id, parsed.txs, auto) do
        result =
          Repo.transaction(fn ->
            Enum.reduce(parsed.txs, {0, 0}, fn tx, {imported, journal_count} ->
              if tx.reference != "" and tx.reference in refs do
                {imported, journal_count}
              else
                case Dec.parse(tx.amount) do
                  nil ->
                    {imported, journal_count}

                  amount ->
                    tx_type = if amount < 0, do: "WITHDRAWAL", else: "DEPOSIT"
                    currency = if tx.currency == "", do: ba.currency, else: tx.currency

                    row =
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
                        is_booked: if(auto, do: 1, else: 0),
                        is_allocated: 0
                      })

                    if auto do
                      {:ok, entry} = auto_journal(company_id, ba, tx, amount, tx_type)
                      Repo.update!(Ecto.Changeset.change(row, journal_entry_id: entry))
                      abs_s = Dec.money(Dec.abs(amount))

                      Audit.record(
                        company_id,
                        sub,
                        "journal",
                        entry,
                        tx.reference,
                        "create",
                        "Импортирана банкова транзакция (#{tx.reference}) — #{tx.contra_name}, сума #{abs_s}",
                        "",
                        abs_s,
                        nil,
                        nil
                      )

                      {imported + 1, journal_count + 1}
                    else
                      {imported + 1, journal_count}
                    end
                end
              end
            end)
          end)

        case result do
          {:ok, {imported, journal_count}} ->
            {:ok, %{imported: imported, journal_count: journal_count}}

          {:error, reason} ->
            {:error, {500, inspect(reason)}}
        end
      end
    end
  end

  defp check_periods(_company_id, _txs, false), do: :ok

  defp check_periods(company_id, txs, true) do
    Enum.reduce_while(txs, :ok, fn tx, _acc ->
      case Periods.assert_open(company_id, tx.date) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def book(company_id, sub, id, params) do
    cp = Params.integer(params, "counterpart_id") || 0
    contra = Params.integer(params, "contra_account_id") || 0
    debit = Params.integer(params, "debit_account_id")
    credit = Params.integer(params, "credit_account_id")
    book_tx(company_id, sub, id, contra, cp, debit, credit)
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

  defp detect(content) do
    case Csv.detect(content) do
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

  defp auto_journal(company_id, ba, tx, amount, tx_type) do
    abs_s = Dec.money(Dec.abs(amount))

    {debit_id, credit_id} =
      if tx_type == "DEPOSIT",
        do: {ba.gl_account_id, ba.buffer_account_id},
        else: {ba.buffer_account_id, ba.gl_account_id}

    with {:ok, debit} <- account_by_id(debit_id, company_id),
         {:ok, credit} <- account_by_id(credit_id, company_id) do
      desc =
        if ba.name in [nil, ""], do: "Банково извлечение", else: "Банково извлечение #{ba.name}"

      desc = if tx.description in [nil, ""], do: desc, else: "#{desc} — #{tx.description}"

      Journal.write_entry(
        company_id,
        tx.date,
        "bank",
        0,
        tx.reference,
        desc,
        0,
        tx.contra_name,
        month_of(tx.date),
        [
          %{account: debit, direction: "debit", amount: abs_s},
          %{account: credit, direction: "credit", amount: abs_s}
        ]
      )
    end
  end

  defp month_of(date), do: if(String.length(date) >= 7, do: String.slice(date, 0, 7), else: date)

  defp tx_json(t) do
    %{
      id: t.id,
      bank_account_id: t.bank_account_id,
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

defmodule Botyaga.Banking.Tx.Book do
  @moduledoc """
  Ръчно осчетоводяване, връщане в чернова и разнасяне на банкови транзакции
  (подмодул на `Botyaga.Banking.Tx`).
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Dec, Journal, Params, Periods, Repo}
  alias Botyaga.Banking.Tx.Internal

  def book(company_id, sub, id, params) do
    with :ok <- confirmed(params) do
      if Internal.lines_given?(params) do
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
    with {:ok, tx} <- Internal.tx_row(company_id, id),
         :ok <- Internal.booked(tx),
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
    if Internal.lines_given?(params) do
      Internal.lines_preview(company_id, id, params)
    else
      simple_preview(company_id, id, params)
    end
  end

  defp simple_preview(company_id, id, params) do
    cp = Params.integer(params, "counterpart_id") || 0
    contra = Params.integer(params, "contra_account_id") || 0
    debit = Params.integer(params, "debit_account_id")
    credit = Params.integer(params, "credit_account_id")

    with {:ok, tx} <- Internal.tx_row(company_id, id),
         :ok <- Internal.ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- Internal.ensure_ref(Catalog.Account, contra, company_id, "сметката"),
         :ok <- Internal.not_booked(tx),
         {:ok, amount} <- Internal.tx_amount(tx),
         {:ok, ba} <- Internal.bank(company_id, tx.bank_account_id),
         {:ok, debit_id, credit_id} <-
           Internal.sides(ba, contra, debit, credit, amount, company_id),
         :ok <- Periods.assert_open(company_id, tx.txn_date),
         {:ok, debit_acc} <- Internal.account_by_id(debit_id, company_id),
         {:ok, credit_acc} <- Internal.account_by_id(credit_id, company_id) do
      abs_s = Dec.money(Dec.abs(amount))

      {:ok,
       %{
         transaction_id: tx.id,
         date: tx.txn_date,
         amount: abs_s,
         currency: tx.currency,
         description: Internal.base_desc(tx),
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
    with {:ok, tx} <- Internal.tx_row(company_id, id),
         :ok <- Internal.ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- Internal.ensure_ref(Catalog.Account, contra, company_id, "сметката"),
         :ok <- Internal.not_booked(tx),
         {:ok, amount} <- Internal.tx_amount(tx),
         {:ok, ba} <- Internal.bank(company_id, tx.bank_account_id),
         {:ok, debit_id, credit_id} <-
           Internal.sides(ba, contra, debit_opt, credit_opt, amount, company_id),
         {:ok, cp_name} <- Internal.counterpart_name(cp, company_id),
         :ok <- Periods.assert_open(company_id, tx.txn_date),
         {:ok, debit} <- Internal.account_by_id(debit_id, company_id),
         {:ok, credit} <- Internal.account_by_id(credit_id, company_id) do
      abs_s = Dec.money(Dec.abs(amount))
      shown = if cp > 0, do: cp_name, else: tx.counterpart_name
      desc = Internal.base_desc(tx)

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
          Internal.month_of(tx.txn_date),
          [
            %{account: debit, direction: "debit", amount: abs_s},
            %{account: credit, direction: "credit", amount: abs_s}
          ]
        )

      Repo.update!(
        Ecto.Changeset.change(tx, is_booked: 1, is_allocated: 1, journal_entry_id: entry)
      )

      Internal.apply_fx(entry, tx, company_id, abs_s)

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

    with {:ok, tx} <- Internal.tx_row(company_id, id),
         :ok <- Internal.not_booked(tx),
         :ok <- Internal.ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         {:ok, ba} <- Internal.bank(company_id, tx.bank_account_id),
         {:ok, date} <- Internal.entry_date(params, tx),
         :ok <- Periods.assert_open(company_id, date),
         {:ok, lines} <- Internal.parse_lines(params, company_id),
         :ok <- Internal.check_balanced(lines),
         :ok <- Internal.ensure_bank_line(lines, ba),
         {:ok, cp_name} <- Internal.counterpart_name(cp, company_id) do
      desc = Internal.param_desc(params, tx)
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
          Internal.month_of(date),
          sides
        )

      Repo.update!(
        Ecto.Changeset.change(tx, is_booked: 1, is_allocated: 1, journal_entry_id: entry)
      )

      {debit, _credit} = Internal.line_totals(lines)

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
    with {:ok, new_acc} <- Internal.req_id(params, "account_id") do
      cp = Params.integer(params, "counterpart_id") || 0
      reallocate_tx(company_id, sub, id, new_acc, cp)
    end
  end

  def reallocate_tx(company_id, sub, id, new_acc, cp) do
    with {:ok, tx} <- Internal.tx_row(company_id, id),
         :ok <- Internal.ensure_ref(Catalog.Account, new_acc, company_id, "сметката"),
         :ok <- Internal.ensure_ref(Catalog.Counterpart, cp, company_id, "контрагентът"),
         :ok <- Internal.has_entry(tx),
         {:ok, ba} <- Internal.bank(company_id, tx.bank_account_id),
         :ok <- Internal.has_buffer(ba),
         {:ok, cp_name} <- Internal.counterpart_name(cp, company_id),
         {:ok, acct} <- Internal.account_by_id(new_acc, company_id) do
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
end

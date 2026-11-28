defmodule Botyaga.Banking.Tx do
  @moduledoc """
  Банкови транзакции: преглед, импорт, ръчно осчетоводяване и разнасяне.

  Импортът НЕ създава счетоводни записи — транзакциите остават „нови“.
  Всяка транзакция се осчетоводява само след изрично потвърждение:
  `book_preview` връща предложения запис (Дт/Кт) без да пише в базата,
  а `book` изисква `confirm=true` и едва тогава създава статията.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Dec, Journal, Params, Repo}
  alias Botyaga.Banking.{Account, Transaction}
  alias Botyaga.Banking.Tx.{Book, Internal}

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
    |> Enum.map(&Internal.tx_json(&1, Map.get(names, &1.bank_account_id)))
  end

  defp keep?(t, "new"), do: t.is_booked == 0
  defp keep?(t, "booked"), do: t.is_booked != 0 and t.is_allocated == 0
  defp keep?(t, "allocated"), do: t.is_allocated != 0
  defp keep?(_, _), do: true

  def preview(company_id, params) do
    with {:ok, ba_id} <- Internal.req_id(params, "bank_account_id"),
         {:ok, content} <- Internal.required(params, "file_content"),
         {:ok, ba} <- Internal.bank(company_id, ba_id),
         {:ok, parsed} <- Internal.detect(content, ba.statement_format) do
      refs = Internal.refs_of(ba_id)
      {txs, dup} = Internal.mark_duplicates(parsed.txs, refs)
      {:ok, Internal.pack(parsed, txs, dup)}
    end
  end

  def import(company_id, _sub, params) do
    with {:ok, ba_id} <- Internal.req_id(params, "bank_account_id"),
         {:ok, content} <- Internal.required(params, "file_content"),
         {:ok, ba} <- Internal.bank(company_id, ba_id),
         {:ok, parsed} <- Internal.detect(content, ba.statement_format) do
      refs = Internal.refs_of(ba_id)

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

  def book(company_id, sub, id, params), do: Book.book(company_id, sub, id, params)

  @doc """
  Връща осчетоводена транзакция в чернова: статията се изтрива, флаговете се
  нулират. Само в чернова банковите транзакции могат да се редактират (пре-
  осчетоводяват) отново.
  """
  def unbook(company_id, sub, id), do: Book.unbook(company_id, sub, id)

  def book_preview(company_id, id, params), do: Book.book_preview(company_id, id, params)

  def book_tx(company_id, sub, id, contra, cp, debit_opt, credit_opt),
    do: Book.book_tx(company_id, sub, id, contra, cp, debit_opt, credit_opt)

  def reallocate(company_id, sub, id, params),
    do: Book.reallocate(company_id, sub, id, params)

  def reallocate_tx(company_id, sub, id, new_acc, cp),
    do: Book.reallocate_tx(company_id, sub, id, new_acc, cp)

  def delete(company_id, sub, id) do
    with {:ok, tx} <- Internal.tx_row(company_id, id) do
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
end

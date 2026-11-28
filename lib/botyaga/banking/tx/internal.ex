defmodule Botyaga.Banking.Tx.Internal do
  @moduledoc """
  Вътрешни помощни функции на `Botyaga.Banking.Tx` — споделени между главния
  модул и `Botyaga.Banking.Tx.Book`: валидации, парсване на банков импорт,
  помощници за редове на статии и JSON отговори.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Companies, Dec, Journal, Params, Periods, Rates, Repo}
  alias Botyaga.Banking.{Account, Formats, Transaction}

  @unknown "Непознат формат на файла. Поддържаните формати са: OBB XML, ISO camt.053, PostBank XML, MT-940, CSV."

  def lines_given?(params) do
    case Map.get(params, "lines") do
      arr when is_list(arr) -> arr != []
      _ -> false
    end
  end

  def lines_preview(company_id, id, params) do
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

  def entry_date(params, tx) do
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

  def param_desc(params, tx) do
    case Params.str(params, "description") do
      {:present, v} ->
        v = String.trim(v)
        if v == "", do: base_desc(tx), else: v

      _ ->
        base_desc(tx)
    end
  end

  def parse_lines(params, company_id) do
    case Map.get(params, "lines") do
      arr when is_list(arr) and arr != [] -> parse_each(arr, 0, [], company_id)
      _ -> {:error, {422, "lines е задължително и не може да е празен"}}
    end
  end

  def parse_each([], _index, acc, _company_id), do: {:ok, Enum.reverse(acc)}

  def parse_each([item | rest], index, acc, company_id) when is_map(item) do
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

  def parse_each(_, index, _acc, _company_id),
    do: {:error, {422, "lines[#{index}] трябва да е обект"}}

  def line_str(item, key) do
    case Params.str(item, key) do
      {:present, v} -> v
      _ -> ""
    end
  end

  def line_totals(lines) do
    Enum.reduce(lines, {0, 0}, fn l, {d, c} ->
      if l.direction == "debit", do: {d + l.cents, c}, else: {d, c + l.cents}
    end)
  end

  def check_balanced(lines) do
    {debit, credit} = line_totals(lines)

    if debit == credit do
      :ok
    else
      {:error, {422, "записът не е балансиран: Дт=#{Dec.money(debit)} Кт=#{Dec.money(credit)}"}}
    end
  end

  # Когато банковата сметка има свързана ГЛ сметка, записът задължително
  # трябва да я съдържа — иначе банковото движение не се отразява.
  def ensure_bank_line(lines, %Account{gl_account_id: gl}) when gl > 0 do
    if Enum.any?(lines, &(&1.account_id == gl)) do
      :ok
    else
      {:error, {422, "записът трябва да съдържа банковата ГЛ сметка на транзакцията"}}
    end
  end

  def ensure_bank_line(_lines, _ba), do: :ok

  def line_json(l) do
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

  def booked(%Transaction{is_booked: v}) when v != 0, do: :ok
  def booked(_), do: {:error, {409, "транзакцията не е осчетоводена"}}

  def detect(content, hint) do
    case Formats.detect(content, hint) do
      nil -> {:error, {422, @unknown}}
      parsed -> {:ok, parsed}
    end
  end

  def mark_duplicates(txs, refs) do
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

  def pack(parsed, txs, dup) do
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

  def refs_of(ba_id) do
    Repo.all(from(t in Transaction, where: t.bank_account_id == ^ba_id, select: t.reference))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  def bank(company_id, id) do
    case Repo.get_by(Account, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "Банковата сметка не е намерена"}}
      account -> {:ok, account}
    end
  end

  def tx_row(company_id, id) do
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

  def not_booked(%Transaction{is_booked: 0}), do: :ok
  def not_booked(_), do: {:error, {409, "транзакцията вече е осчетоводена"}}

  def tx_amount(tx) do
    case Dec.parse(tx.amount) do
      nil -> {:error, {422, "невалидна сума на транзакцията"}}
      amount -> {:ok, amount}
    end
  end

  def sides(ba, contra, debit_opt, credit_opt, amount, company_id) do
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

  def has_entry(%Transaction{journal_entry_id: entry}) when entry > 0, do: :ok
  def has_entry(_), do: {:error, {422, "Транзакцията няма счетоводен запис"}}

  def has_buffer(%Account{buffer_account_id: buf}) when buf > 0, do: :ok
  def has_buffer(_), do: {:error, {422, "Няма буферна сметка"}}

  def counterpart_name(cp, _company_id) when cp <= 0, do: {:ok, ""}

  def counterpart_name(cp, company_id) do
    case Repo.get_by(Catalog.Counterpart, id: cp, company_id: company_id) do
      nil -> {:error, {404, "Контрагентът не е намерен"}}
      counterpart -> {:ok, counterpart.name}
    end
  end

  def account_by_id(id, company_id) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company_id) do
      nil -> {:error, {422, "липсва сметка с id #{id}"}}
      account -> {:ok, account}
    end
  end

  def ensure_ref(_schema, id, _company_id, _what) when id <= 0, do: :ok

  def ensure_ref(schema, id, company_id, what) do
    if Repo.get_by(schema, id: id, company_id: company_id) == nil do
      {:error, {404, "#{what} не е намерен"}}
    else
      :ok
    end
  end

  def base_desc(tx) do
    desc = if tx.description in [nil, ""], do: "Ръчно осчетоводяване", else: tx.description
    if tx.counterpart_name in [nil, ""], do: desc, else: "#{desc} - #{tx.counterpart_name}"
  end

  def apply_fx(entry, tx, company_id, abs_s) do
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

  def base_currency(company_id) do
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

  def month_of(date), do: if(String.length(date) >= 7, do: String.slice(date, 0, 7), else: date)

  def tx_json(t, ba_name) do
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

  def req_id(params, key) do
    case Params.integer(params, key) do
      nil -> {:error, {422, "#{key} е задължително"}}
      {:error, _} -> {:error, {422, "#{key} е задължително"}}
      value when value <= 0 -> {:error, {422, "#{key} е задължително"}}
      value -> {:ok, value}
    end
  end

  def required(params, key) do
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

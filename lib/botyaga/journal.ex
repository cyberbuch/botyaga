defmodule Botyaga.Journal do
  @moduledoc """
  Дневник: четене и ръчни записи. Само записи без фактура (`manual`) могат да
  се променят; приключвателните могат да се трият. Ръчният запис е в транзакция.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Catalog, Params, Periods, Repo}
  alias Botyaga.Invoicing.Money
  alias Botyaga.Journal.{Entry, Line}

  @manual "manual"
  @closing "closing"

  def list(company_id) do
    entries =
      Repo.all(from(e in Entry, where: e.company_id == ^company_id, order_by: [asc: e.id]))

    stamps = Audit.stamps_for(company_id, "journal")

    Enum.map(entries, fn entry ->
      entry |> entry_json() |> Audit.attach_stamp(Map.get(stamps, entry.id))
    end)
  end

  def show(company_id, id) do
    case get_entry(company_id, id) do
      nil -> {:error, {404, "записът не е намерен"}}
      entry -> {:ok, full_json(company_id, entry)}
    end
  end

  def create(company_id, sub, params) do
    with {:ok, attrs} <- parse_entry(params, 0),
         {:ok, lines} <- parse_lines(params),
         :ok <- check_balanced(lines),
         :ok <- ensure_accounts(company_id, lines),
         :ok <- Periods.assert_open(company_id, attrs.entry_date) do
      result =
        Repo.transaction(fn ->
          entry =
            Repo.insert!(%Entry{
              company_id: company_id,
              entry_date: attrs.entry_date,
              document_type: attrs.document_type,
              document_id: 0,
              document_number: attrs.document_number,
              description: attrs.description,
              vat_type: attrs.vat_type,
              counterpart_id: attrs.counterpart_id,
              counterpart_name: attrs.counterpart_name,
              document_date: attrs.document_date,
              vat_period: attrs.vat_period
            })

          entry =
            if attrs.document_number == "",
              do: %{entry | document_number: "MANUAL-#{entry.id}"},
              else: entry

          entry =
            Repo.update!(Ecto.Changeset.change(entry, document_number: entry.document_number))

          write_lines(entry.id, lines, company_id)
          entry
        end)

      case result do
        {:ok, entry} ->
          value = full_json(company_id, entry)

          Audit.record(
            company_id,
            sub,
            "journal",
            entry.id,
            entry.document_number,
            "create",
            "Създадена ръчна статия #{entry.document_number} (#{entry.entry_date}) — #{entry.description} [#{accounts_summary(value)}], оборот #{debit_total(value)}",
            "",
            debit_total(value),
            nil,
            value
          )

          {:ok, full_json(company_id, entry)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, entry} <- fetch_manual(company_id, id),
         {:ok, attrs} <- parse_entry(params, id),
         {:ok, lines} <- parse_lines(params),
         :ok <- check_balanced(lines),
         :ok <- ensure_accounts(company_id, lines),
         :ok <- Periods.assert_open(company_id, attrs.entry_date) do
      before = full_json(company_id, entry)

      {:ok, entry} =
        Repo.transaction(fn ->
          entry =
            Repo.update!(
              Ecto.Changeset.change(entry,
                entry_date: attrs.entry_date,
                document_type: attrs.document_type,
                document_number: attrs.document_number,
                description: attrs.description,
                vat_type: attrs.vat_type,
                counterpart_id: attrs.counterpart_id,
                counterpart_name: attrs.counterpart_name,
                document_date: attrs.document_date,
                vat_period: attrs.vat_period
              )
            )

          Repo.delete_all(from(l in Line, where: l.entry_id == ^entry.id))
          write_lines(entry.id, lines, company_id)
          entry
        end)

      value = full_json(company_id, entry)

      Audit.record(
        company_id,
        sub,
        "journal",
        entry.id,
        entry.document_number,
        "update",
        "Редактирана счетоводна статия #{entry.document_number} (#{entry.entry_date}) — #{entry.description}",
        debit_total(before),
        debit_total(value),
        before,
        value
      )

      {:ok, value}
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, entry} <- fetch_deletable(company_id, id),
         :ok <- Periods.assert_open(company_id, entry.entry_date) do
      before = full_json(company_id, entry)
      wipe(entry.id)

      Audit.record(
        company_id,
        sub,
        "journal",
        entry.id,
        entry.document_number,
        "delete",
        "Изтрита счетоводна статия #{entry.document_number} (#{entry.entry_date}) — #{entry.description}, оборот #{debit_total(before)}",
        debit_total(before),
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  def bulk_delete(company_id, sub, ids) do
    {done, failed, results} =
      Enum.reduce(ids, {0, 0, []}, fn id, {done, failed, results} ->
        case delete(company_id, sub, id) do
          {:ok, nil} ->
            {done + 1, failed, results ++ [%{id: id, ok: 1}]}

          {:error, {_status, detail}} ->
            {done, failed + 1, results ++ [%{id: id, ok: 0, error: detail}]}
        end
      end)

    %{deleted: done, failed: failed, results: results}
  end

  @doc "Общ запис за банка, ДМА, производство и склад — `vat_type` е `no_vat`."
  def write_entry(
        company_id,
        date,
        doc_type,
        doc_id,
        doc_number,
        desc,
        counterpart_id,
        counterpart_name,
        vat_period,
        sides
      ) do
    Repo.transaction(fn ->
      entry =
        Repo.insert!(%Entry{
          company_id: company_id,
          entry_date: date,
          document_type: doc_type,
          document_id: doc_id,
          document_number: doc_number,
          description: desc,
          vat_type: "no_vat",
          counterpart_id: counterpart_id,
          counterpart_name: counterpart_name,
          document_date: date,
          vat_period: vat_period
        })

      Enum.each(sides, fn side ->
        Repo.insert!(%Line{
          entry_id: entry.id,
          account_id: side.account.id,
          account_number: side.account.number,
          account_name: side.account.name,
          direction: side.direction,
          amount: side.amount,
          vat_amount: "0",
          currency: Map.get(side, :currency, "") || "",
          fx_quantity: Map.get(side, :fx_quantity, side.amount) || side.amount,
          fx_rate: Map.get(side, :fx_rate, "1") || "1"
        })
      end)

      entry.id
    end)
  end

  def wipe(entry_id) when entry_id > 0 do
    Repo.delete_all(from(l in Line, where: l.entry_id == ^entry_id))
    Repo.delete_all(from(e in Entry, where: e.id == ^entry_id))
    :ok
  end

  def wipe(_), do: :ok

  ## Вътрешни

  defp get_entry(company_id, id),
    do: Repo.get_by(Entry, id: Params.id(id), company_id: company_id)

  defp fetch_manual(company_id, id) do
    case get_entry(company_id, id) do
      nil ->
        {:error, {404, "записът не е намерен"}}

      entry ->
        if manual?(entry.document_type),
          do: {:ok, entry},
          else: {:error, {403, "само ръчни записи могат да се редактират"}}
    end
  end

  defp fetch_deletable(company_id, id) do
    case get_entry(company_id, id) do
      nil ->
        {:error, {404, "записът не е намерен"}}

      entry ->
        if manual?(entry.document_type) or entry.document_type == @closing do
          {:ok, entry}
        else
          {:error, {403, "само ръчни и приключвателни записи могат да се изтриват"}}
        end
    end
  end

  defp manual?(type), do: type in [nil, "", @manual]

  defp parse_entry(params, id) do
    with {:ok, entry_date} <- required(params, "entry_date") do
      description = string(params, "description")
      vat_type = parse_vat_type(string(params, "vat_type"))
      counterpart_id = Params.integer(params, "counterpart_id") || 0

      with :ok <- ensure_counterpart(counterpart_id, params) do
        counterpart_name =
          resolve_counterpart_name(counterpart_id, string(params, "counterpart_name"), params)

        given_no = String.trim(string(params, "document_number"))

        document_number =
          if given_no == "", do: if(id > 0, do: "MANUAL-#{id}", else: ""), else: given_no

        given_date = String.trim(string(params, "document_date"))
        document_date = if given_date == "", do: entry_date, else: given_date
        given_period = String.trim(string(params, "vat_period"))

        with {:ok, vat_period} <- vat_period(given_period, entry_date) do
          given_type = String.trim(string(params, "document_type"))

          document_type =
            if Regex.match?(~r/^[0-9]{2}$/, given_type), do: given_type, else: @manual

          {:ok,
           %{
             entry_date: entry_date,
             document_type: document_type,
             description: description,
             vat_type: vat_type,
             counterpart_id: counterpart_id,
             counterpart_name: counterpart_name,
             document_number: document_number,
             document_date: document_date,
             vat_period: vat_period
           }}
        end
      end
    end
  end

  defp vat_period("", entry_date), do: {:ok, month_of(entry_date)}

  defp vat_period(given, _entry_date) do
    case Botyaga.Vat.Fmt.parse_period(given) do
      {:ok, p} -> {:ok, p.iso}
      {:error, _} -> {:error, {422, "vat_period трябва да е във формат ГГГГ-ММ"}}
    end
  end

  defp ensure_counterpart(counterpart_id, _params) when counterpart_id <= 0, do: :ok

  defp ensure_counterpart(counterpart_id, params) do
    company_id = Map.get(params, :company_id) || Map.get(params, "company_id")

    if company_id &&
         Repo.get_by(Catalog.Counterpart, id: counterpart_id, company_id: company_id) == nil do
      {:error, {404, "контрагентът не е намерен"}}
    else
      :ok
    end
  end

  defp resolve_counterpart_name(counterpart_id, given, params) do
    cond do
      String.trim(given) != "" ->
        String.trim(given)

      counterpart_id <= 0 ->
        ""

      true ->
        company_id = Map.get(params, :company_id) || Map.get(params, "company_id")

        case company_id &&
               Repo.get_by(Catalog.Counterpart, id: counterpart_id, company_id: company_id) do
          %Catalog.Counterpart{name: name} -> name || ""
          _ -> ""
        end
    end
  end

  defp parse_vat_type(raw) do
    case String.trim(raw) do
      "purchase" -> "purchase"
      "sales" -> "sales"
      _ -> "no_vat"
    end
  end

  defp parse_lines(params) do
    case Map.get(params, "lines") do
      nil ->
        {:error, {422, "lines е задължително"}}

      arr when is_list(arr) ->
        if arr == [] do
          {:error, {422, "lines не може да е празен"}}
        else
          parse_each(arr, 0, [])
        end

      _ ->
        {:error, {422, "lines е задължително"}}
    end
  end

  defp parse_each([], _index, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_each([item | rest], index, acc) when is_map(item) do
    account_id = Params.integer(item, "account_id") || 0
    direction = item |> string("direction") |> String.trim()
    amount = item |> string("amount") |> String.trim()
    vat_amount = item |> string("vat_amount", "0") |> String.trim()
    currency = item |> string("currency") |> String.trim() |> String.upcase()
    fx_quantity = item |> string("fx_quantity") |> String.trim()
    fx_rate = item |> string("fx_rate", "1") |> String.trim()

    cond do
      account_id <= 0 ->
        {:error, {422, "lines[#{index}].account_id е задължителен"}}

      direction not in ["debit", "credit"] ->
        {:error, {422, "lines[#{index}].direction трябва да е debit или credit"}}

      amount in ["", "0", "0.00"] ->
        {:error, {422, "lines[#{index}].amount не може да е 0"}}

      true ->
        line = %{
          account_id: account_id,
          direction: direction,
          amount: amount,
          vat_amount: vat_amount,
          currency: currency,
          fx_quantity: if(fx_quantity == "", do: amount, else: fx_quantity),
          fx_rate: if(fx_rate == "", do: "1", else: fx_rate)
        }

        parse_each(rest, index + 1, [line | acc])
    end
  end

  defp parse_each(_, index, _acc), do: {:error, {422, "lines[#{index}] трябва да е обект"}}

  defp check_balanced(lines) do
    {debit, credit} =
      Enum.reduce(lines, {0, 0}, fn line, {debit, credit} ->
        case Money.cents(line.amount) do
          nil ->
            throw({:error, {422, "невалидна сума: #{line.amount}"}})

          cents ->
            if line.direction == "debit",
              do: {debit + cents, credit},
              else: {debit, credit + cents}
        end
      end)

    if debit == credit do
      :ok
    else
      {:error,
       {422, "записът не е балансиран: Дт=#{Money.money(debit)} Кт=#{Money.money(credit)}"}}
    end
  catch
    {:error, _} = error -> error
  end

  defp ensure_accounts(company_id, lines) do
    Enum.reduce_while(lines, :ok, fn line, _acc ->
      if Repo.get_by(Catalog.Account, id: line.account_id, company_id: company_id) == nil do
        {:halt, {:error, {404, "сметката не е намерен"}}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp write_lines(entry_id, lines, company_id) do
    Enum.each(lines, fn line ->
      account = Repo.get_by!(Catalog.Account, id: line.account_id, company_id: company_id)

      Repo.insert!(%Line{
        entry_id: entry_id,
        account_id: line.account_id,
        account_number: account.number,
        account_name: account.name,
        direction: line.direction,
        amount: line.amount,
        vat_amount: line.vat_amount,
        currency: line.currency,
        fx_quantity: line.fx_quantity,
        fx_rate: line.fx_rate
      })
    end)
  end

  defp entry_json(entry) do
    %{
      id: entry.id,
      company_id: entry.company_id,
      entry_date: entry.entry_date,
      document_type: entry.document_type,
      document_id: entry.document_id,
      document_number: entry.document_number,
      description: entry.description,
      vat_type: entry.vat_type,
      counterpart_id: entry.counterpart_id,
      counterpart_name: entry.counterpart_name,
      document_date: entry.document_date,
      vat_period: entry.vat_period
    }
  end

  defp full_json(company_id, entry) do
    lines = Repo.all(from(l in Line, where: l.entry_id == ^entry.id, order_by: [asc: l.id]))

    value =
      entry
      |> entry_json()
      |> Map.put(:lines, Enum.map(lines, &line_json/1))
      |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, "journal"), entry.id))

    Map.put(value, :audit_history, Audit.history_for(company_id, "journal", entry.id))
  end

  defp line_json(line) do
    %{
      id: line.id,
      account_id: line.account_id,
      direction: line.direction,
      amount: line.amount,
      vat_amount: line.vat_amount,
      account_number: line.account_number,
      account_name: line.account_name,
      currency: line.currency,
      fx_quantity: line.fx_quantity,
      fx_rate: line.fx_rate
    }
  end

  defp debit_total(value) do
    value
    |> Map.get(:lines, [])
    |> Enum.filter(&(&1.direction == "debit"))
    |> Enum.map(&(Money.cents(&1.amount) || 0))
    |> Enum.sum()
    |> Money.money()
  end

  defp accounts_summary(value) do
    lines = Map.get(value, :lines, [])

    debits =
      lines
      |> Enum.filter(&(&1.direction == "debit"))
      |> Enum.map(& &1.account_number)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    credits =
      lines
      |> Enum.filter(&(&1.direction == "credit"))
      |> Enum.map(& &1.account_number)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    "Дт #{Enum.join(debits, ",")} / Кт #{Enum.join(credits, ",")}"
  end

  defp month_of(date) do
    if String.length(date) >= 7, do: String.slice(date, 0, 7), else: date
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, String.trim(value)}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

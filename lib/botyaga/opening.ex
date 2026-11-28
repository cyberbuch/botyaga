defmodule Botyaga.Opening do
  @moduledoc """
  Начални салда. Не се пишат в дневника (салдо не е оборот). Януари на
  фискалната година трябва да е отворен. Страната следва номера по НСС.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Periods, Repo}
  alias Botyaga.Invoicing.Money
  alias Botyaga.Periods.OpeningBalance

  def natural_side(number) do
    d0 = String.slice(number, 0, 1)

    cond do
      d0 == "1" ->
        "credit"

      d0 == "2" ->
        if String.starts_with?(number, "24"), do: "credit", else: "debit"

      d0 == "3" ->
        "debit"

      d0 == "4" ->
        cond do
          String.starts_with?(number, "4531") -> "debit"
          String.starts_with?(number, "4532") -> "credit"
          String.starts_with?(number, "40") -> "credit"
          String.starts_with?(number, "41") -> "debit"
          true -> "any"
        end

      d0 in ["5", "6"] ->
        "debit"

      d0 == "7" ->
        "credit"

      true ->
        "any"
    end
  end

  def account_kind(number) do
    d0 = String.slice(number, 0, 1)

    case d0 do
      "1" ->
        "capital"

      "2" ->
        "fixed_asset"

      "3" ->
        "inventory"

      "4" ->
        cond do
          String.starts_with?(number, "40") -> "payable"
          String.starts_with?(number, "41") -> "receivable"
          true -> "settlement"
        end

      "5" ->
        "cash"

      "6" ->
        "expense"

      "7" ->
        "revenue"

      _ ->
        "other"
    end
  end

  def index(company_id, year_param) do
    year = year_of(year_param)

    rows =
      Repo.all(
        from(o in OpeningBalance,
          where: o.company_id == ^company_id and o.fiscal_year == ^year,
          order_by: [asc: o.id]
        )
      )

    {accounts, cps, prs} = maps(company_id)

    {items, td, tc} =
      Enum.reduce(rows, {[], 0, 0}, fn row, {items, td, tc} ->
        item =
          row_json(
            row,
            Map.get(accounts, row.account_id),
            Map.get(cps, row.counterpart_id, ""),
            Map.get(prs, row.product_id, {"", ""})
          )

        td = td + (Money.cents(row.debit) || 0)
        tc = tc + (Money.cents(row.credit) || 0)
        {items ++ [item], td, tc}
      end)

    %{
      items: items,
      count: length(items),
      fiscal_year: year,
      total_debit: Money.money(td),
      total_credit: Money.money(tc),
      difference: Money.money(td - tc)
    }
  end

  def create(company_id, params) do
    with {:ok, year} <- required_int(params, "fiscal_year"),
         {:ok, account_id} <- required_int(params, "account_id") do
      debit = string(params, "debit", "0")
      credit = string(params, "credit", "0")
      counterpart_id = Params.integer(params, "counterpart_id") || 0
      product_id = Params.integer(params, "product_id") || 0
      quantity = string(params, "quantity", "0")
      description = string(params, "description")

      with :ok <- Periods.assert_open(company_id, "#{year}-01"),
           {:ok, account} <- ensure_account(company_id, account_id),
           :ok <- check_amounts(account, debit, credit),
           :ok <- check_money(quantity, "количеството"),
           :ok <- ensure_ref(Catalog.Counterpart, counterpart_id, company_id, "контрагентът"),
           :ok <- ensure_ref(Catalog.Product, product_id, company_id, "артикулът"),
           :ok <- check_analytic(account, counterpart_id, product_id) do
        Repo.insert!(%OpeningBalance{
          company_id: company_id,
          fiscal_year: year,
          account_id: account_id,
          debit: debit,
          credit: credit,
          counterpart_id: counterpart_id,
          product_id: product_id,
          quantity: quantity,
          description: description
        })

        {:ok,
         %{
           status: "created",
           natural_side: natural_side(account.number),
           account_kind: account_kind(account.number)
         }}
      end
    end
  end

  def update(company_id, id, params) do
    with {:ok, row} <- load(company_id, id),
         :ok <- Periods.assert_open(company_id, "#{row.fiscal_year}-01") do
      changes = %{}

      changes =
        Enum.reduce(~w(debit credit description quantity), changes, fn field, acc ->
          case Params.str(params, field) do
            {:present, value} -> Map.put(acc, String.to_existing_atom(field), value)
            _ -> acc
          end
        end)

      with {:ok, changes} <-
             put_ref(
               changes,
               params,
               "counterpart_id",
               Catalog.Counterpart,
               company_id,
               "контрагентът"
             ),
           {:ok, changes} <-
             put_ref(changes, params, "product_id", Catalog.Product, company_id, "артикулът"),
           {:ok, account} <- ensure_account(company_id, row.account_id),
           :ok <-
             check_amounts(
               account,
               Map.get(changes, :debit, row.debit),
               Map.get(changes, :credit, row.credit)
             ),
           :ok <- check_money(Map.get(changes, :quantity, row.quantity), "количеството"),
           :ok <-
             check_analytic(
               account,
               Map.get(changes, :counterpart_id, row.counterpart_id),
               Map.get(changes, :product_id, row.product_id)
             ) do
        row = if changes == %{}, do: row, else: Repo.update!(Ecto.Changeset.change(row, changes))
        {accounts, cps, prs} = maps(company_id)

        {:ok,
         row_json(
           row,
           Map.get(accounts, row.account_id),
           Map.get(cps, row.counterpart_id, ""),
           Map.get(prs, row.product_id, {"", ""})
         )}
      end
    end
  end

  def delete(company_id, id) do
    with {:ok, row} <- load(company_id, id),
         :ok <- Periods.assert_open(company_id, "#{row.fiscal_year}-01") do
      Repo.delete!(row)
      {:ok, nil}
    end
  end

  ## Вътрешни

  defp load(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(OpeningBalance, id: id, company_id: company_id) do
        nil -> {:error, {404, "Opening balance not found"}}
        row -> {:ok, row}
      end
    end
  end

  defp maps(company_id) do
    accounts =
      Repo.all(from(a in Catalog.Account, where: a.company_id == ^company_id))
      |> Map.new(&{&1.id, &1})

    cps =
      Repo.all(from(c in Catalog.Counterpart, where: c.company_id == ^company_id))
      |> Map.new(&{&1.id, &1.name})

    prs =
      Repo.all(from(p in Catalog.Product, where: p.company_id == ^company_id))
      |> Map.new(&{&1.id, {&1.name, &1.code}})

    {accounts, cps, prs}
  end

  defp row_json(row, account, cp_name, {pr_name, pr_code}) do
    base = %{
      id: row.id,
      fiscal_year: row.fiscal_year,
      account_id: row.account_id,
      debit: row.debit,
      credit: row.credit,
      counterpart_id: row.counterpart_id,
      product_id: row.product_id,
      quantity: row.quantity,
      description: row.description
    }

    base =
      if account do
        Map.merge(base, %{
          account_number: account.number,
          account_name: account.name,
          analytic_type: account.analytic_type,
          natural_side: natural_side(account.number),
          account_kind: account_kind(account.number)
        })
      else
        base
      end

    base =
      if row.counterpart_id > 0 and cp_name != "",
        do: Map.put(base, :counterpart_name, cp_name),
        else: base

    if row.product_id > 0 and pr_name != "" do
      Map.merge(base, %{product_name: pr_name, product_code: pr_code})
    else
      base
    end
  end

  defp ensure_account(company_id, account_id) do
    case Repo.get_by(Catalog.Account, id: account_id, company_id: company_id) do
      nil -> {:error, {404, "записът не е намерен"}}
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

  defp check_side(account, debit, credit) do
    side = natural_side(account.number)

    cond do
      side == "debit" and not zero?(credit) ->
        {:error, {422, "#{account.number} е дебитна по НСС — началното салдо е в дебит"}}

      side == "credit" and not zero?(debit) ->
        {:error, {422, "#{account.number} е кредитна по НСС — началното салдо е в кредит"}}

      true ->
        :ok
    end
  end

  defp check_analytic(account, counterpart_id, product_id) do
    cond do
      account.analytic_type == "counterpart" and counterpart_id <= 0 ->
        {:error, {422, "#{account.number} е аналитична към контрагент"}}

      account.analytic_type == "product" and product_id <= 0 ->
        {:error, {422, "#{account.number} е аналитична към продукт"}}

      true ->
        :ok
    end
  end

  defp put_ref(changes, params, key, schema, company_id, what) do
    case Params.integer(params, key) do
      nil ->
        {:ok, changes}

      {:error, message} ->
        {:error, {422, message}}

      value ->
        with :ok <- ensure_ref(schema, value, company_id, what) do
          {:ok, Map.put(changes, String.to_existing_atom(key), value)}
        end
    end
  end

  defp zero?(raw) do
    case Money.cents(raw) do
      nil -> true
      0 -> true
      _ -> false
    end
  end

  defp check_money(raw, what) do
    if Money.cents(raw) == nil do
      {:error, {422, "невалидно #{what}"}}
    else
      :ok
    end
  end

  # Едни и същи правила при create и update: валидни суми, или дебит, или
  # кредит, и салдото да е от правилната страна на сметката.
  defp check_amounts(account, debit, credit) do
    cond do
      Money.cents(debit) == nil ->
        {:error, {422, "невалидна сума в дебит"}}

      Money.cents(credit) == nil ->
        {:error, {422, "невалидна сума в кредит"}}

      zero?(debit) and zero?(credit) ->
        {:error, {422, "въведете дебит или кредит"}}

      not zero?(debit) and not zero?(credit) ->
        {:error, {422, "салдото е или дебит, или кредит — не и двете"}}

      true ->
        check_side(account, debit, credit)
    end
  end

  defp year_of(raw) do
    n = raw |> to_string() |> String.trim() |> to_int()
    if n < 2000, do: 2026, else: n
  end

  defp required_int(params, key) do
    case Params.integer(params, key) do
      nil -> {:error, {422, "#{key} е задължително"}}
      {:error, message} -> {:error, {422, message}}
      value -> {:ok, value}
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end

  defp to_int(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

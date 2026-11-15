defmodule Botyaga.Banking do
  @moduledoc "Банкови сметки на фирма. Салдото е низ с два знака."

  import Ecto.Query

  alias Botyaga.{Catalog, Companies, Dec, Params, Repo}
  alias Botyaga.Banking.Account

  def list(company_id) do
    Repo.all(
      from(a in Account, where: a.company_id == ^company_id, order_by: [asc: a.name, asc: a.id])
    )
    |> Enum.map(&one(&1, company_id))
  end

  def get(company_id, id) do
    case Repo.get_by(Account, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "Bank account not found"}}
      account -> {:ok, one(account, company_id)}
    end
  end

  def create(company_id, params) do
    with {:ok, name} <- required(params, "name"),
         {:ok, iban} <- required(params, "iban"),
         {:ok, balance} <- norm_balance(string(params, "balance", "0")),
         {:ok, gl} <- ref(params, "gl_account_id", company_id),
         {:ok, buf} <- ref(params, "buffer_account_id", company_id),
         :ok <- unique_iban(company_id, iban, 0) do
      account = %Account{
        company_id: company_id,
        name: name,
        iban: iban,
        bic: string(params, "bic"),
        bank_name: string(params, "bank_name"),
        currency: default_currency(params, company_id),
        account_number: string(params, "account_number"),
        gl_account_id: gl,
        buffer_account_id: buf,
        balance: balance
      }

      account = Repo.insert!(account)
      {:ok, one(account, company_id)}
    end
  end

  def update(company_id, id, params) do
    with {:ok, current} <- fetch(company_id, id),
         {:ok, name} <- pick(params, "name", current.name),
         {:ok, iban} <- pick(params, "iban", current.iban),
         :ok <- present(name, "name"),
         :ok <- present(iban, "iban"),
         :ok <- unique_iban(company_id, iban, current.id),
         {:ok, balance} <- balance(params, current.balance),
         {:ok, gl} <- pick_ref(params, "gl_account_id", current.gl_account_id, company_id),
         {:ok, buf} <-
           pick_ref(params, "buffer_account_id", current.buffer_account_id, company_id) do
      account =
        Repo.update!(
          Ecto.Changeset.change(current,
            name: name,
            iban: iban,
            bic: pick_string(params, "bic", current.bic),
            bank_name: pick_string(params, "bank_name", current.bank_name),
            currency: pick_string(params, "currency", current.currency),
            account_number: pick_string(params, "account_number", current.account_number),
            balance: balance,
            gl_account_id: gl,
            buffer_account_id: buf
          )
        )

      {:ok, one(account, company_id)}
    end
  end

  def delete(company_id, id) do
    with {:ok, account} <- fetch(company_id, id) do
      Repo.delete!(account)
      {:ok, nil}
    end
  end

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Account, id: id, company_id: company_id) do
        nil -> {:error, {404, "Bank account not found"}}
        account -> {:ok, account}
      end
    end
  end

  defp one(account, company_id) do
    base = %{
      id: account.id,
      iban: account.iban,
      bic: account.bic,
      bank_name: account.bank_name,
      currency: account.currency,
      name: account.name,
      account_number: account.account_number,
      gl_account_id: account.gl_account_id,
      buffer_account_id: account.buffer_account_id,
      balance: account.balance,
      company_id: account.company_id
    }

    base = put_code(base, :gl_account_code, account.gl_account_id, company_id)
    put_code(base, :buffer_account_code, account.buffer_account_id, company_id)
  end

  defp put_code(base, _key, id, _company_id) when id <= 0, do: base

  defp put_code(base, key, id, company_id) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company_id) do
      %{number: number} when number not in [nil, ""] -> Map.put(base, key, number)
      _ -> base
    end
  end

  defp default_currency(params, company_id) do
    case Params.str(params, "currency") do
      {:present, value} when value != "" -> value
      _ -> company_currency(company_id)
    end
  end

  defp company_currency(company_id) do
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

  defp unique_iban(company_id, iban, except_id) do
    if Repo.exists?(
         from(a in Account,
           where: a.company_id == ^company_id and a.iban == ^iban and a.id != ^except_id
         )
       ) do
      {:error, {409, "IBAN вече съществува"}}
    else
      :ok
    end
  end

  defp norm_balance(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидно начално салдо"}}
      value -> {:ok, Dec.money(value)}
    end
  end

  defp balance(params, current) do
    case Params.str(params, "balance") do
      {:present, value} -> norm_balance(value)
      _ -> {:ok, current || "0.00"}
    end
  end

  defp ref(params, key, company_id) do
    id = Params.integer(params, key) || 0

    if id <= 0 do
      {:ok, 0}
    else
      if Repo.get_by(Catalog.Account, id: id, company_id: company_id) == nil do
        {:error, {404, "сметката не е намерен"}}
      else
        {:ok, id}
      end
    end
  end

  defp pick_ref(params, key, current, company_id) do
    case Params.integer(params, key) do
      nil -> {:ok, current}
      {:error, message} -> {:error, {422, message}}
      id -> ref(%{key => id}, key, company_id)
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> {:ok, value}
      _ -> {:ok, current}
    end
  end

  defp pick_string(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  defp present(value, key) do
    if String.trim(value || "") == "", do: {:error, {422, "#{key} е задължително"}}, else: :ok
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

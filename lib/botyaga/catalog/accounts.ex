defmodule Botyaga.Catalog.Accounts do
  @moduledoc "Сметкоплан на фирма: четене, запис и seed от каталога на НАП."

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Catalog.Account

  @analytic ~w(none counterpart product)
  @analytic_message "analytic_type е none, counterpart или product"

  def list(company_id) do
    Repo.all(from(a in Account, where: a.company_id == ^company_id, order_by: [asc: a.number]))
  end

  def get(company_id, id) do
    case Repo.get_by(Account, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "сметката не е намерена"}}
      account -> {:ok, account}
    end
  end

  def create(company_id, params) do
    with {:ok, number} <- required(params, "number"),
         {:ok, name} <- required(params, "name"),
         {:ok, analytic} <- analytic(params) do
      number = String.trim(number)

      if number_taken?(company_id, number, 0) do
        {:error, {409, "номерът вече съществува"}}
      else
        account = %Account{
          company_id: company_id,
          number: number,
          name: String.trim(name),
          saft_account_type: String.trim(string(params, "saft_account_type")),
          analytic_type: analytic,
          is_currency: currency_flag(params, number)
        }

        {:ok, Repo.insert!(account)}
      end
    end
  end

  def update(company_id, id, params) do
    with {:ok, account} <- get(company_id, id),
         {:ok, number} <- optional_required(params, "number", account.number),
         {:ok, name} <- optional_required(params, "name", account.name),
         {:ok, analytic} <- analytic(params, account.analytic_type) do
      number = String.trim(number)

      if number_taken?(company_id, number, Params.id(id)) do
        {:error, {409, "номерът вече съществува"}}
      else
        changes = %{
          number: number,
          name: String.trim(name),
          saft_account_type:
            String.trim(string(params, "saft_account_type", account.saft_account_type)),
          analytic_type: analytic,
          is_currency: currency_flag(params, number, account.is_currency)
        }

        {:ok, Repo.update!(Ecto.Changeset.change(account, changes))}
      end
    end
  end

  def delete(company_id, id) do
    with {:ok, account} <- get(company_id, id) do
      Repo.delete!(account)
      {:ok, nil}
    end
  end

  def seed(company_id) do
    {created, skipped} = Catalog.seed_chart(company_id)
    %{created: created, skipped: skipped, total: created + skipped}
  end

  @doc "Сметка по номер; ако липсва, се създава от каталога на НАП."
  def ensure_by_number(company_id, number) do
    case Repo.get_by(Account, company_id: company_id, number: number) do
      %Account{id: id} ->
        id

      nil ->
        name = Catalog.account_name(number) || number

        account = %Account{
          company_id: company_id,
          number: number,
          name: name,
          saft_account_type: number,
          analytic_type: "none"
        }

        Repo.insert!(account).id
    end
  end

  defp number_taken?(company_id, number, except_id) do
    Repo.exists?(
      from(a in Account,
        where: a.company_id == ^company_id and a.number == ^number and a.id != ^except_id
      )
    )
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

  defp optional_required(params, key, current) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:ok, current}
    end
  end

  defp analytic(params, current \\ "none") do
    case Params.str(params, "analytic_type") do
      :absent ->
        {:ok, current}

      {:present, value} ->
        value = String.trim(value)
        if value in @analytic, do: {:ok, value}, else: {:error, {422, @analytic_message}}

      {:error, _} ->
        {:error, {422, @analytic_message}}
    end
  end

  defp currency_flag(params, number, current \\ nil) do
    case Map.fetch(params, "is_currency") do
      {:ok, v} when is_boolean(v) ->
        if(v, do: 1, else: 0)

      _ ->
        if is_nil(current) do
          if String.starts_with?(number, "4") or String.starts_with?(number, "5"), do: 1, else: 0
        else
          current
        end
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

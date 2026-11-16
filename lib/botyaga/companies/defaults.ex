defmodule Botyaga.Companies.Defaults do
  @moduledoc """
  Default сметки за автоматизация. Пазят се в `settings.default_accounts` на
  фирмата като двойки роля → номер на сметка. Липсваща роля ползва стандартния
  номер от сметкоплана; липсваща сметка в базата е грешка при осчетоводяване.
  """

  alias Botyaga.{Catalog, Repo}

  @roles ~w(customers suppliers vat_purchase vat_sale cash bank
            card_purchase card_sale revenues expenses)

  @fallback %{
    "customers" => "411",
    "suppliers" => "401",
    "vat_purchase" => "4531",
    "vat_sale" => "4532",
    "cash" => "501",
    "bank" => "503",
    "revenues" => "702",
    "expenses" => "602"
  }

  def roles, do: @roles

  @doc "Картата default_accounts от настройките на фирмата."
  def map(%{settings: raw}) do
    case Jason.decode(raw || "") do
      {:ok, %{"default_accounts" => m}} when is_map(m) -> m
      _ -> %{}
    end
  end

  @doc "Номерът на сметката за роля: зададеният или стандартният."
  def number(company, role) do
    case Map.get(map(company), role) do
      n when is_binary(n) ->
        case String.trim(n) do
          "" -> Map.get(@fallback, role, "")
          trimmed -> trimmed
        end

      _ ->
        Map.get(@fallback, role, "")
    end
  end

  @doc "Сметката за роля в рамките на фирмата."
  def resolve(company, role) do
    num = number(company, role)

    cond do
      num == "" ->
        {:error, {422, "няма default сметка за „#{role}“ — задайте я в настройките на фирмата"}}

      true ->
        case Repo.get_by(Catalog.Account, number: num, company_id: company.id) do
          nil -> {:error, {422, "липсва сметка с номер #{num}"}}
          account -> {:ok, account}
        end
    end
  end
end

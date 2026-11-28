defmodule Botyaga.Production.Cards.Validate do
  @moduledoc """
  Валидация на входните данни на производствена карта спрямо фирмата:
  продуктите и сметките от params трябва да принадлежат на активната фирма
  (проверка срещу IDOR — чужд product_id/account_id дава 422).
  """

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Production.CardProduct

  @doc "Разбира и валидира редовете „products“ — всеки product_id е на фирмата."
  def parse_products(company_id, params) do
    arr = Map.get(params, "products") || []

    Enum.reduce_while(arr, {:ok, []}, fn p, {:ok, acc} ->
      pid = Params.integer(p, "product_id") || 0

      case product_of(company_id, pid) do
        {:ok, product} ->
          {:cont,
           {:ok,
            acc ++
              [
                %{
                  product_id: pid,
                  quantity: pick(p, "quantity", "0"),
                  coefficient: pick(p, "coefficient", "1"),
                  manual_amount: pick(p, "manual_amount", ""),
                  inventory_account_id: (product && product.inventory_account_id) || 0
                }
              ]}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  def parse_products_opt(company_id, params) do
    if Map.has_key?(params, "products") do
      parse_products(company_id, params)
    else
      {:ok, []}
    end
  end

  def product_of(_company_id, pid) when pid <= 0, do: {:ok, nil}

  def product_of(company_id, pid) do
    case Repo.get_by(Catalog.Product, id: pid, company_id: company_id) do
      nil -> {:error, {422, "стоката не е намерена"}}
      product -> {:ok, product}
    end
  end

  @doc "Сметките от params трябва да са на активната фирма (0 = „няма“)."
  def ensure_card_accounts(company_id, params) do
    with :ok <- opt_account_id(company_id, params, "materials_account_id"),
         :ok <- opt_account_id(company_id, params, "production_account_id"),
         :ok <- opt_account_list(company_id, params, "direct_accounts"),
         :ok <- opt_account_list(company_id, params, "common_accounts") do
      :ok
    end
  end

  defp opt_account_id(company_id, params, key) do
    case Map.get(params, key) do
      nil -> :ok
      id when is_integer(id) -> ensure_account_id(company_id, id)
      other -> ensure_account_id(company_id, Params.integer(%{key => other}, key) || 0)
    end
  end

  defp opt_account_list(company_id, params, key) do
    case Map.get(params, key) do
      nil ->
        :ok

      list when is_list(list) ->
        Enum.reduce_while(list, :ok, fn id, :ok ->
          case ensure_account_id(company_id, id || 0) do
            :ok -> {:cont, :ok}
            err -> {:halt, err}
          end
        end)

      _ ->
        :ok
    end
  end

  defp ensure_account_id(_company_id, id) when id <= 0, do: :ok

  defp ensure_account_id(company_id, id) do
    if Repo.get_by(Catalog.Account, id: id, company_id: company_id) == nil do
      {:error, {422, "сметката не е намерена във фирмата"}}
    else
      :ok
    end
  end

  def insert_products(card_id, products) do
    Enum.each(products, fn p ->
      %CardProduct{}
      |> Ecto.Changeset.change(%{
        card_id: card_id,
        product_id: p.product_id,
        quantity: p.quantity,
        coefficient: p.coefficient,
        manual_amount: p.manual_amount,
        inventory_account_id: p.inventory_account_id
      })
      |> Repo.insert!()
    end)
  end

  defp pick(params, key, default) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> default
    end
  end
end

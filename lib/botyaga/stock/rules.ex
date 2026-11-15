defmodule Botyaga.Stock.Rules do
  @moduledoc "Правила за изписване: goods/production/material. Номера на сметки не се подставят."

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Stock.Rule

  def load(company_id) do
    Repo.all(from(r in Rule, where: r.company_id == ^company_id, order_by: [asc: r.id]))
  end

  def pair(rules, kind, inventory, offset) do
    Enum.find(rules, fn r ->
      r.kind == kind and r.inventory_account_id == inventory and r.offset_account_id == offset
    end)
  end

  def material_inventory(rules, inventory) do
    Enum.find(rules, fn r ->
      r.kind == "material" and r.inventory_account_id == inventory and inventory > 0
    end)
  end

  def material_line_allowed(company_id, rules, product_id, inventory, offset) do
    case Repo.get_by(Catalog.Product, id: product_id, company_id: company_id) do
      nil ->
        false

      product ->
        if product.inventory_account_id != inventory or product.auto_write_off == 1 do
          false
        else
          pair(rules, "material", inventory, offset) != nil or
            (product.expense_account_id > 0 and product.expense_account_id == offset)
        end
    end
  end

  def check_production(company_id, output_id, lines) do
    rules = load(company_id)

    with {:ok, out} <- named(company_id, output_id) do
      case pair(rules, "production", out.inventory, out.revenue) do
        %{clearing_account_id: clearing} when clearing > 0 ->
          check_materials(company_id, rules, lines)

        _ ->
          {:error, {422, "няма правило за продукция за #{out.name}"}}
      end
    end
  end

  defp check_materials(_company_id, _rules, []), do: :ok

  defp check_materials(company_id, rules, [line | rest]) do
    pid = line["product_id"] || line[:product_id] || 0

    if pid <= 0 do
      {:error, {422, "ред без артикул"}}
    else
      with {:ok, mat} <- named(company_id, pid) do
        if material_inventory(rules, mat.inventory) == nil do
          {:error, {422, "няма правило за материал за #{mat.name}"}}
        else
          check_materials(company_id, rules, rest)
        end
      end
    end
  end

  defp named(company_id, id) do
    case Repo.get_by(Catalog.Product, id: id, company_id: company_id) do
      nil ->
        {:error, {422, "артикулът не е намерен"}}

      product ->
        {:ok,
         %{
           name: product.name,
           inventory: product.inventory_account_id,
           revenue: product.revenue_account_id
         }}
    end
  end

  ## CRUD

  def index(company_id) do
    load(company_id) |> Enum.map(&rule_json/1)
  end

  def create(company_id, params) do
    with {:ok, kind} <- required(params, "kind"),
         :ok <- kind_ok(kind),
         {:ok, inventory} <- account_ok(params, "inventory_account_id", company_id),
         {:ok, offset} <- account_ok(params, "offset_account_id", company_id),
         {:ok, clearing} <- clearing(params, kind, company_id) do
      rule =
        Repo.insert!(%Rule{
          company_id: company_id,
          kind: kind,
          inventory_account_id: inventory,
          offset_account_id: offset,
          clearing_account_id: clearing
        })

      {:ok, rule_json(rule)}
    end
  end

  def delete(company_id, id) do
    case Repo.get_by(Rule, id: Params.id(id), company_id: company_id) do
      nil ->
        {:error, {404, "правилото не е намерено"}}

      rule ->
        Repo.delete!(rule)
        {:ok, nil}
    end
  end

  defp rule_json(r) do
    %{
      id: r.id,
      kind: r.kind,
      inventory_account_id: r.inventory_account_id,
      offset_account_id: r.offset_account_id,
      clearing_account_id: r.clearing_account_id
    }
  end

  defp kind_ok(kind) do
    if kind in ["goods", "production", "material"],
      do: :ok,
      else: {:error, {422, "видът е goods, production или material"}}
  end

  defp account_ok(params, key, company_id) do
    id = Params.integer(params, key) || 0

    cond do
      id <= 0 ->
        {:error, {422, "сметката е задължителна"}}

      Repo.get_by(Catalog.Account, id: id, company_id: company_id) == nil ->
        {:error, {422, "липсва сметка с id #{id}"}}

      true ->
        {:ok, id}
    end
  end

  defp clearing(params, "production", company_id),
    do: account_ok(params, "clearing_account_id", company_id)

  defp clearing(_params, _kind, _company_id), do: {:ok, 0}

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, String.trim(value)}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end
end

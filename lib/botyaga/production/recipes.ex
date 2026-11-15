defmodule Botyaga.Production.Recipes do
  @moduledoc "Рецепти за производство. Редовете се подменят цели при запис."

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Params, Repo}
  alias Botyaga.Production.{Recipe, RecipeLine}

  def index(company_id) do
    Repo.all(from(r in Recipe, where: r.company_id == ^company_id, order_by: [asc: r.id]))
    |> Enum.map(&head/1)
  end

  def show(company_id, id) do
    with {:ok, recipe} <- fetch(company_id, id) do
      {:ok, Map.put(head(recipe), :lines, lines_json(recipe.id))}
    end
  end

  def create(company_id, params) do
    with {:ok, fields} <- fields(params, nil),
         {:ok, lines} <- lines(params),
         :ok <- ensure_product(fields.output_product_id, company_id),
         :ok <- ensure_lines(lines, company_id) do
      {:ok, recipe} =
        Repo.transaction(fn ->
          recipe = Repo.insert!(struct(%Recipe{company_id: company_id}, fields))
          write_lines(recipe.id, lines)
          recipe
        end)

      show(company_id, recipe.id)
    end
  end

  def update(company_id, id, params) do
    with {:ok, current} <- fetch(company_id, id),
         {:ok, fields} <- fields(params, current),
         :ok <- ensure_product(fields.output_product_id, company_id) do
      new_lines = if Map.has_key?(params, "lines"), do: lines(params), else: {:ok, nil}

      with {:ok, new_lines} <- new_lines,
           :ok <- ensure_lines(new_lines || [], company_id) do
        {:ok, recipe} =
          Repo.transaction(fn ->
            recipe = Repo.update!(Ecto.Changeset.change(current, fields))

            if new_lines do
              Repo.delete_all(from(l in RecipeLine, where: l.recipe_id == ^recipe.id))
              write_lines(recipe.id, new_lines)
            end

            recipe
          end)

        show(company_id, recipe.id)
      end
    end
  end

  def delete(company_id, id) do
    with {:ok, recipe} <- fetch(company_id, id) do
      Repo.delete_all(from(l in RecipeLine, where: l.recipe_id == ^recipe.id))
      Repo.delete!(recipe)
      {:ok, nil}
    end
  end

  @doc "Рецепта с редовете за производство."
  def load_recipe(company_id, id) do
    with {:ok, recipe} <- fetch(company_id, id) do
      lines =
        Repo.all(
          from(l in RecipeLine,
            where: l.recipe_id == ^recipe.id,
            order_by: [asc: l.line_no, asc: l.id]
          )
        )

      {:ok,
       %{
         output_id: recipe.output_product_id,
         output_qty: recipe.output_quantity,
         lines:
           Enum.map(
             lines,
             &%{
               product_id: &1.product_id,
               quantity: &1.quantity,
               unit: &1.unit,
               wastage: &1.wastage_percent
             }
           )
       }}
    end
  end

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Recipe, id: id, company_id: company_id) do
        nil -> {:error, {404, "Рецептата не е намерена"}}
        recipe -> {:ok, recipe}
      end
    end
  end

  defp head(r) do
    %{
      id: r.id,
      code: r.code,
      name: r.name,
      output_product_id: r.output_product_id,
      output_quantity: r.output_quantity,
      output_unit: r.output_unit,
      notes: r.notes,
      is_active: r.is_active
    }
  end

  defp lines_json(recipe_id) do
    Repo.all(
      from(l in RecipeLine,
        where: l.recipe_id == ^recipe_id,
        order_by: [asc: l.line_no, asc: l.id]
      )
    )
    |> Enum.map(fn l ->
      %{
        id: l.id,
        recipe_id: l.recipe_id,
        product_id: l.product_id,
        quantity: l.quantity,
        unit: l.unit,
        wastage_percent: l.wastage_percent,
        line_no: l.line_no
      }
    end)
  end

  defp fields(params, current) do
    name = pick(params, "name", current && current.name)

    if String.trim(name || "") == "" do
      {:error, {422, "name е задължително"}}
    else
      output_id = pick_int(params, "output_product_id", current && current.output_product_id)

      if output_id <= 0 do
        {:error, {422, "изходният артикул е задължителен"}}
      else
        qty_raw = pick(params, "output_quantity", current && current.output_quantity)
        qty_raw = if String.trim(qty_raw || "") == "", do: "1", else: qty_raw

        case Dec.parse(qty_raw) do
          nil ->
            {:error, {422, "невалидна стойност"}}

          value ->
            {:ok,
             %{
               code: pick(params, "code", current && current.code),
               name: name,
               output_product_id: output_id,
               output_quantity: Dec.qty(value),
               output_unit: pick(params, "output_unit", current && current.output_unit),
               notes: pick(params, "notes", current && current.notes),
               is_active: pick_flag(params, "is_active", current && current.is_active, 1)
             }}
        end
      end
    end
  end

  defp lines(params) do
    case Map.get(params, "lines") do
      nil -> {:ok, []}
      arr when is_list(arr) -> parse_lines(arr, [])
      _ -> {:error, {422, "lines трябва да е масив"}}
    end
  end

  defp parse_lines([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_lines([line | rest], acc) when is_map(line) do
    product_id = Params.integer(line, "product_id") || 0

    if product_id <= 0 do
      parse_lines(rest, acc)
    else
      with {:ok, quantity} <- num_text(pick(line, "quantity", "0"), true),
           {:ok, wastage} <- num_text(pick(line, "wastage_percent", "0"), false) do
        parse_lines(rest, [
          %{
            product_id: product_id,
            quantity: quantity,
            unit: pick(line, "unit", ""),
            wastage: wastage
          }
          | acc
        ])
      end
    end
  end

  defp parse_lines(_, _acc), do: {:error, {422, "редът трябва да е обект"}}

  defp num_text(raw, as_qty) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна стойност"}}
      value -> {:ok, if(as_qty, do: Dec.qty(value), else: Dec.text(value, 2))}
    end
  end

  defp write_lines(recipe_id, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, no} ->
      Repo.insert!(%RecipeLine{
        recipe_id: recipe_id,
        product_id: line.product_id,
        quantity: line.quantity,
        unit: line.unit,
        wastage_percent: line.wastage,
        line_no: no
      })
    end)
  end

  defp ensure_product(id, company_id) do
    if id > 0 and Repo.get_by(Catalog.Product, id: id, company_id: company_id) == nil do
      {:error, {404, "артикулът не е намерен"}}
    else
      :ok
    end
  end

  defp ensure_lines(lines, company_id) do
    Enum.reduce_while(lines, :ok, fn line, _acc ->
      case ensure_product(line.product_id, company_id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current || ""
    end
  end

  defp pick_int(params, key, current) do
    case Params.integer(params, key) do
      nil -> current || 0
      {:error, _} -> current || 0
      value -> value
    end
  end

  defp pick_flag(params, key, current, default) do
    case Params.flag(params, key) do
      nil -> current || default
      {:error, _} -> current || default
      value -> value
    end
  end
end

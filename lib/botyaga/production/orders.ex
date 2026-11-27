defmodule Botyaga.Production.Orders do
  @moduledoc """
  Поръчки за производство. Потвърждението маркира поръчката; себестойността
  и записът в дневника идват от преизчислението по правилата.
  """

  import Ecto.Query

  alias Botyaga.{Attachments, Audit, Catalog, Companies, Dec, Params, Periods, Repo}
  alias Botyaga.Production.{Order, OrderLine, Recipes}
  alias Botyaga.Stock.{Replay, Rules}

  def index(company_id) do
    stamps = Audit.stamps_for(company_id, "production_order")

    Repo.all(from(o in Order, where: o.company_id == ^company_id, order_by: [asc: o.id]))
    |> Enum.map(fn o -> o |> one(false) |> Audit.attach_stamp(Map.get(stamps, o.id)) end)
  end

  def show(company_id, id) do
    with {:ok, order} <- fetch(company_id, id) do
      value =
        one(order, true)
        |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, "production_order"), order.id))

      {:ok,
       Map.put(value, :audit_history, Audit.history_for(company_id, "production_order", order.id))}
    end
  end

  def create(company_id, sub, params) do
    recipe_id = Params.integer(params, "recipe_id") || 0

    if recipe_id <= 0 do
      {:error, {422, "рецептата е задължителна"}}
    else
      with {:ok, recipe} <- Recipes.load_recipe(company_id, recipe_id),
           {:ok, raw_quantity} <- required(params, "quantity"),
           {:ok, quantity} <- qty_of(raw_quantity),
           :ok <- positive(quantity),
           {:ok, location_id} <- location(params, company_id),
           :ok <- ensure_product(recipe.output_id, company_id),
           :ok <- ensure_products(recipe.lines, company_id) do
        order_date = string(params, "order_date")
        notes = string(params, "notes")

        {:ok, order} =
          Repo.transaction(fn ->
            order =
              Repo.insert!(%Order{
                company_id: company_id,
                recipe_id: recipe_id,
                output_product_id: recipe.output_id,
                quantity: quantity,
                location_id: location_id,
                order_date: order_date,
                status: "draft",
                notes: notes,
                material_cost: "0.00",
                journal_entry_id: 0,
                recipe_snapshot: snapshot(recipe)
              })

            order = Repo.update!(Ecto.Changeset.change(order, number: "ПР-#{order.id}"))
            copy_lines(order.id, company_id, recipe, quantity)
            order
          end)

        Audit.record(
          company_id,
          sub,
          "production_order",
          order.id,
          order.number,
          "create",
          "Създадена поръчка за производство #{order.number} (#{order_date}), к-во #{quantity}",
          "",
          "0.00",
          nil,
          one(order, true)
        )

        show(company_id, order.id)
      end
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, order} <- fetch(company_id, id),
         :ok <- draft(order) do
      Repo.delete_all(from(l in OrderLine, where: l.order_id == ^order.id))
      Repo.delete!(order)
      Attachments.delete_for(company_id, "production_order", id)

      Audit.record(
        company_id,
        sub,
        "production_order",
        order.id,
        order.number,
        "delete",
        "Изтрита поръчка за производство #{order.number}",
        order.material_cost,
        "",
        one(order, true),
        nil
      )

      {:ok, nil}
    end
  end

  def confirm(company_id, sub, id) do
    with {:ok, order} <- fetch(company_id, id),
         :ok <- not_completed(order),
         :ok <- has_location(order),
         :ok <- has_output(order),
         lines = lines_of(order.id),
         :ok <- has_lines(lines),
         :ok <- Periods.assert_open(company_id, order.order_date),
         :ok <- Rules.check_production(company_id, order.output_product_id, lines) do
      Repo.transaction(fn ->
        Repo.update!(
          Ecto.Changeset.change(order,
            status: "completed",
            material_cost: "0.00",
            journal_entry_id: 0
          )
        )

        Replay.rebuild(company_id, "9999-12-31")
      end)

      {:ok, after_order} = fetch(company_id, id)

      Audit.record(
        company_id,
        sub,
        "production_order",
        id,
        after_order.number,
        "post",
        "Потвърдена поръчка за производство #{after_order.number} (#{order.order_date}), себестойност #{after_order.material_cost}",
        "0.00",
        after_order.material_cost,
        one(order, true),
        one(after_order, true)
      )

      show(company_id, id)
    end
  end

  ## Вътрешни

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Order, id: id, company_id: company_id) do
        nil -> {:error, {404, "Поръчката не е намерена"}}
        order -> {:ok, order}
      end
    end
  end

  @doc "Копие на поръчка: същите продукти/количества по рецепта, с днешна дата. Ръчните корекции остават само в оригинала."
  def copy(company_id, sub, id) do
    with {:ok, order} <- fetch(company_id, id) do
      create(company_id, sub, %{
        "recipe_id" => order.recipe_id,
        "quantity" => order.quantity,
        "order_date" => Date.to_iso8601(Date.utc_today()),
        "location_id" => order.location_id,
        "notes" => "Копие на #{order.number}"
      })
    end
  end

  defp snapshot(recipe) do
    Jason.encode!(%{
      output_qty: recipe.output_qty,
      lines:
        Enum.map(recipe.lines, fn l ->
          %{product_id: l.product_id, quantity: l.quantity, unit: l.unit, wastage: l.wastage}
        end)
    })
  end

  defp decode_snapshot(nil), do: nil

  defp decode_snapshot(raw) do
    case Jason.decode(raw) do
      {:ok, m} -> m
      _ -> nil
    end
  end

  defp one(order, with_lines) do
    base = %{
      id: order.id,
      number: order.number,
      recipe_id: order.recipe_id,
      output_product_id: order.output_product_id,
      quantity: order.quantity,
      location_id: order.location_id,
      order_date: order.order_date,
      status: order.status,
      notes: order.notes,
      material_cost: order.material_cost,
      journal_entry_id: order.journal_entry_id
    }

    base = Map.put(base, :recipe_snapshot, decode_snapshot(order.recipe_snapshot))

    if with_lines, do: Map.put(base, :lines, lines_json(order.id)), else: base
  end

  defp lines_of(order_id) do
    Repo.all(from(l in OrderLine, where: l.order_id == ^order_id, order_by: [asc: l.id]))
    |> Enum.map(fn l -> %{"product_id" => l.product_id} end)
  end

  defp lines_json(order_id) do
    Repo.all(from(l in OrderLine, where: l.order_id == ^order_id, order_by: [asc: l.id]))
    |> Enum.map(fn l ->
      %{
        id: l.id,
        product_id: l.product_id,
        product_name: l.product_name,
        quantity: l.quantity,
        norm_quantity: l.norm_quantity,
        unit: l.unit,
        unit_cost: l.unit_cost,
        amount: l.amount
      }
    end)
  end

  defp copy_lines(order_id, company_id, recipe, order_qty) do
    Enum.each(recipe.lines, fn line ->
      need = scale(line.quantity, order_qty, recipe.output_qty, line.wastage)
      name = product_name(line.product_id, company_id)

      Repo.insert!(%OrderLine{
        order_id: order_id,
        product_id: line.product_id,
        product_name: name,
        quantity: need,
        norm_quantity: need,
        unit: line.unit,
        unit_cost: "0.000000",
        amount: "0.00"
      })
    end)
  end

  defp scale(line_qty, order_qty, output_qty, wastage) do
    line = Dec.or0(line_qty)
    order = Dec.or0(order_qty)
    out = Dec.or0(output_qty)
    out = if out <= 0, do: Dec.parse("1"), else: out
    base = Dec.div(Dec.mul(line, order), out) || 0

    factor =
      Dec.add(Dec.parse("1"), Dec.div(Dec.or0(wastage), Dec.parse("100")) || 0) || Dec.parse("1")

    Dec.qty(Dec.mul(base, factor))
  end

  defp product_name(id, company_id) do
    case Repo.get_by(Catalog.Product, id: id, company_id: company_id) do
      nil -> ""
      product -> product.name
    end
  end

  defp qty_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна стойност"}}
      value -> {:ok, Dec.qty(value)}
    end
  end

  defp positive(quantity) do
    if Dec.or0(quantity) <= 0,
      do: {:error, {422, "количеството трябва да е по-голямо от 0"}},
      else: :ok
  end

  defp location(params, company_id) do
    id = Params.integer(params, "location_id") || 0

    if id > 0 and Repo.get_by(Companies.Location, id: id, company_id: company_id) == nil do
      {:error, {404, "обектът не е намерен"}}
    else
      {:ok, id}
    end
  end

  defp ensure_product(id, company_id) do
    if id > 0 and Repo.get_by(Catalog.Product, id: id, company_id: company_id) == nil do
      {:error, {404, "артикулът не е намерен"}}
    else
      :ok
    end
  end

  defp ensure_products(lines, company_id) do
    Enum.reduce_while(lines, :ok, fn line, _acc ->
      case ensure_product(line.product_id, company_id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp draft(%Order{status: "draft"}), do: :ok
  defp draft(_), do: {:error, {422, "завършена поръчка не се изтрива"}}

  defp not_completed(%Order{status: "completed"}),
    do: {:error, {409, "поръчката е вече завършена"}}

  defp not_completed(_), do: :ok

  defp has_location(%Order{location_id: loc}) when loc > 0, do: :ok
  defp has_location(_), do: {:error, {422, "нужен е складов обект"}}

  defp has_output(%Order{output_product_id: out}) when out > 0, do: :ok
  defp has_output(_), do: {:error, {422, "липсва изходен артикул"}}

  defp has_lines([]), do: {:error, {422, "поръчката няма материали"}}
  defp has_lines(_), do: :ok

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

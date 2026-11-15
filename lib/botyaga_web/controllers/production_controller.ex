defmodule BotyagaWeb.ProductionController do
  use BotyagaWeb, :controller

  alias Botyaga.Companies
  alias Botyaga.Production.{Orders, Recipes}
  alias BotyagaWeb.{Render, Respond}

  ## Рецепти

  def recipes(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Recipes.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.show(company_id, id) do
      Respond.ok(conn, recipe)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.create(company_id, params) do
      Respond.ok(conn, recipe, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.update(company_id, id, params) do
      Respond.ok(conn, recipe)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Recipes.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Поръчки

  def orders(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Orders.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.show(company_id, id) do
      Respond.ok(conn, order)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, order, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Orders.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, order)
    else
      error -> Respond.error(conn, error)
    end
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} when company_id > 0 -> {:ok, company_id}
      {:ok, _} -> {:error, {422, "няма избрана активна фирма"}}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

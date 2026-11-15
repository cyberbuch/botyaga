defmodule BotyagaWeb.AssetsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Assets, Companies}
  alias Botyaga.Assets.Ops
  alias BotyagaWeb.{Render, Respond}

  ## Категории

  def categories(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Assets.categories() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def category_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, category} <- Assets.category_create(company_id, params) do
      Respond.ok(conn, category, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def category_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, category} <- Assets.category_update(company_id, id, params) do
      Respond.ok(conn, category)
    else
      error -> Respond.error(conn, error)
    end
  end

  def category_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Assets.category_delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Активи

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Assets.list() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, asset} <- Assets.get(company_id, id) do
      Respond.ok(conn, asset)
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, asset} <- Assets.create(company_id, params) do
      Respond.ok(conn, asset, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, asset} <- Assets.update(company_id, id, params) do
      Respond.ok(conn, asset)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Assets.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Операции

  def depreciation_preview(conn, _params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Ops.preview(company_id) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def depreciation_post(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Ops.post_dep(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, data, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def revalue(conn, %{"id" => id} = params), do: op(conn, id, params, &Ops.revalue/3)
  def move(conn, %{"id" => id} = params), do: op(conn, id, params, &Ops.move/3)
  def conserve(conn, %{"id" => id} = params), do: op(conn, id, params, &Ops.conserve/3)
  def end_conserve(conn, %{"id" => id} = params), do: op(conn, id, params, &Ops.end_conserve/3)
  def dispose(conn, %{"id" => id} = params), do: op(conn, id, params, &Ops.dispose/3)

  def events(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, items} <- Ops.events(company_id, id) do
      Respond.ok(conn, Render.page(items, params))
    else
      error -> Respond.error(conn, error)
    end
  end

  defp op(conn, id, params, fun) do
    with {:ok, company_id} <- active(conn),
         {:ok, asset} <- fun.(company_id, id, params) do
      Respond.ok(conn, asset)
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

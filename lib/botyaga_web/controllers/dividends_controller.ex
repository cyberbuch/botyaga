defmodule BotyagaWeb.DividendsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Dividends}
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      data = Dividends.index(company_id)
      page = Render.page(data.items, params)
      Respond.ok(conn, Map.merge(page, %{owners: data.owners, currency: data.currency}))
    else
      error -> Respond.error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, dist} <- Dividends.show(company_id, id) do
      Respond.ok(conn, dist)
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, dist} <- Dividends.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, dist, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, dist} <-
           Dividends.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, dist)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Dividends.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def pay(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, dist} <- Dividends.pay(company_id, id, params) do
      Respond.ok(conn, dist)
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

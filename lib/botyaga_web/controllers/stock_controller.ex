defmodule BotyagaWeb.StockController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Stock}
  alias Botyaga.Stock.{Rules, Writeoff}
  alias BotyagaWeb.Respond

  def rules(conn, _params) do
    with {:ok, company_id} <- active(conn) do
      items = Rules.index(company_id)
      Respond.ok(conn, %{items: items, count: length(items)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def create_rule(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, rule} <- Rules.create(company_id, params) do
      Respond.ok(conn, rule, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_rule(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Rules.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def rebuild(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Writeoff.rebuild(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def writeoff(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Writeoff.post(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def report(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Stock.report(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def at_location(conn, params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Stock.at_location(company_id, params["location_id"]))
    else
      error -> Respond.error(conn, error)
    end
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} -> {:ok, company_id}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

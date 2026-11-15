defmodule BotyagaWeb.FsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, FsFormulas}
  alias BotyagaWeb.Respond

  def lines(conn, params) do
    with {:ok, data} <- FsFormulas.lines(Map.get(params, "statement", "")) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def index(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- FsFormulas.index(company_id, Map.get(params, "statement", "")) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def put(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- FsFormulas.put(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def defaults(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- FsFormulas.defaults(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def clear(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- FsFormulas.clear(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def validate(conn, params) do
    with {:ok, data} <- FsFormulas.validate(params) do
      Respond.ok(conn, data)
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

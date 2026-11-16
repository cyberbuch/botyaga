defmodule BotyagaWeb.ViesController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Vies}
  alias BotyagaWeb.Respond

  def lookup(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Vies.lookup(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data, status} <- Vies.create(company_id, params) do
      Respond.ok(conn, data, status)
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

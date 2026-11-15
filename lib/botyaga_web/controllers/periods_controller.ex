defmodule BotyagaWeb.PeriodsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Periods}
  alias BotyagaWeb.Respond

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Periods.index(company_id, params["year"]))
    else
      error -> Respond.error(conn, error)
    end
  end

  def close(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Periods.close(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def reopen(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Periods.reopen(company_id, params) do
      Respond.ok(conn, data)
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

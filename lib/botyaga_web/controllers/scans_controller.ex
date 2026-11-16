defmodule BotyagaWeb.ScansController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Scan, Ubl}
  alias BotyagaWeb.Respond

  def ubl(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Ubl.Import.import(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def extract(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Scan.extract(company_id, params) do
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

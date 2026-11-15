defmodule BotyagaWeb.ReportsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Reports}
  alias BotyagaWeb.Respond

  def index(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, body} <- Reports.index(company_id, params) do
      Respond.ok(conn, body)
    else
      error -> Respond.error(conn, error)
    end
  end

  # Експортът на файлове (PDF/XLSX/ODS) зависи от печата — фаза 9.
  def export(conn, _params) do
    Respond.error(conn, {501, "експортът на файлове (PDF/XLSX/ODS) идва с печата — фаза 9"})
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

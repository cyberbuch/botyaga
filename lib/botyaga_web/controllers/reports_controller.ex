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

  # Експорт на файлове: PDF (Chromium sidecar), XLSX и ODS (нативно).
  def export(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, result} <- Reports.export(company_id, params) do
      Respond.attachment(conn, result.bytes, result.mime, result.filename)
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

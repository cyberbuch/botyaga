defmodule BotyagaWeb.PnmapController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Pnmap}
  alias BotyagaWeb.Respond

  def index(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, page} <- Pnmap.index(company_id, params) do
      Respond.ok(conn, page)
    else
      error -> Respond.error(conn, error)
    end
  end

  def save(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, page} <- Pnmap.save(company_id, params) do
      Respond.ok(conn, page)
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

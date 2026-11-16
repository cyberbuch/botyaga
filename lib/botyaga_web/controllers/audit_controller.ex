defmodule BotyagaWeb.AuditController do
  use BotyagaWeb, :controller

  alias Botyaga.{Audit, Companies}
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      items = Audit.index(company_id, params)
      Respond.ok(conn, Render.page(items, params))
    else
      error -> Respond.error(conn, error)
    end
  end

  def entity_history(conn, %{"entity_type" => entity_type, "entity_id" => entity_id}) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Audit.entity_history(company_id, entity_type, entity_id))
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

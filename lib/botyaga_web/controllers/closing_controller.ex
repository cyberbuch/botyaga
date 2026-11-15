defmodule BotyagaWeb.ClosingController do
  use BotyagaWeb, :controller

  alias Botyaga.{Closing, Companies}
  alias BotyagaWeb.Respond

  def preview(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Closing.preview(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def run(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Closing.run(company_id, conn.assigns.current_user.username, params) do
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

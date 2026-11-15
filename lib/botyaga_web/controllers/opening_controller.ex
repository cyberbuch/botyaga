defmodule BotyagaWeb.OpeningController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Opening}
  alias BotyagaWeb.Respond

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Opening.index(company_id, params["year"]))
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Opening.create(company_id, params) do
      Respond.ok(conn, data, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Opening.update(company_id, id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Opening.delete(company_id, id) do
      Respond.no_content(conn)
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

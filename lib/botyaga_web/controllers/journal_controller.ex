defmodule BotyagaWeb.JournalController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Journal, Params}
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Journal.list() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, entry} <- Journal.show(company_id, id) do
      Respond.ok(conn, entry)
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, entry} <-
           Journal.create(
             company_id,
             conn.assigns.current_user.username,
             with_company(params, company_id)
           ) do
      Respond.ok(conn, entry, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, entry} <-
           Journal.update(
             company_id,
             conn.assigns.current_user.username,
             id,
             with_company(params, company_id)
           ) do
      Respond.ok(conn, entry)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Journal.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def bulk_delete(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, ids} <- Params.bulk_ids(params) do
      Respond.ok(conn, Journal.bulk_delete(company_id, conn.assigns.current_user.username, ids))
    else
      error -> Respond.error(conn, error)
    end
  end

  defp with_company(params, company_id), do: Map.put(params, "company_id", company_id)

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} -> {:ok, company_id}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

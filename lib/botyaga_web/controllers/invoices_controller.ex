defmodule BotyagaWeb.InvoicesController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Invoicing, Params}
  alias Botyaga.Invoicing.Post
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Invoicing.list() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, invoice} <-
           Invoicing.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, invoice, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, invoice} <- Invoicing.detail(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, invoice)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, invoice} <-
           Invoicing.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, invoice)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Invoicing.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def next_number(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Invoicing.next_number(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def post(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, body} <- Post.post(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, body, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def bulk_post(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, ids} <- Params.bulk_ids(params) do
      Respond.ok(conn, Post.bulk_post(company_id, conn.assigns.current_user.username, ids))
    else
      error -> Respond.error(conn, error)
    end
  end

  def bulk_unpost(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, ids} <- Params.bulk_ids(params) do
      Respond.ok(conn, Post.bulk_unpost(company_id, conn.assigns.current_user.username, ids))
    else
      error -> Respond.error(conn, error)
    end
  end

  def bulk_delete(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, ids} <- Params.bulk_ids(params) do
      Respond.ok(conn, Invoicing.bulk_delete(company_id, conn.assigns.current_user.username, ids))
    else
      error -> Respond.error(conn, error)
    end
  end

  def issue_protocol(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, invoice} <-
           Invoicing.Special.issue_protocol(
             company_id,
             conn.assigns.current_user.username,
             id,
             params
           ) do
      Respond.ok(conn, invoice, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def issue_customs(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, invoice} <-
           Invoicing.Special.issue_customs(
             company_id,
             conn.assigns.current_user.username,
             id,
             params
           ) do
      Respond.ok(conn, invoice, 201)
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

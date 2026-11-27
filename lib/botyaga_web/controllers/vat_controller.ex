defmodule BotyagaWeb.VatController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Vat}
  alias Botyaga.Vat.Operations
  alias BotyagaWeb.{Render, Respond}

  def registers(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, body} <- Vat.registers(company_id, params["period"] || "") do
      Respond.ok(conn, body)
    else
      error -> Respond.error(conn, error)
    end
  end

  def export(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, file} <- Vat.export(company_id, params["period"] || "", params) do
      conn
      |> put_resp_header("content-type", file.mime)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{file.filename}"))
      |> send_resp(200, file.data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def manual_save(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, body} <- Vat.manual_save(company_id, params["period"] || "", params) do
      Respond.ok(conn, body)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Междинна настройка „ДДС операции“

  def operations_index(conn, _params) do
    with {:ok, company_id} <- active(conn) do
      Operations.seed(company_id)
      Respond.ok(conn, %{items: Operations.list(company_id)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def operations_codes(conn, _params) do
    Respond.ok(conn, %{purchase: Operations.purchase_codes(), sales: Operations.sales_codes()})
  end

  def operations_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, op} <- Operations.create(company_id, params) do
      Respond.ok(conn, op, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def operations_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         %{} = op <- Operations.get(company_id, id),
         {:ok, updated} <- Operations.update(op, params) do
      Respond.ok(conn, updated)
    else
      nil -> Respond.error(conn, {404, "операцията не е намерена"})
      error -> Respond.error(conn, error)
    end
  end

  def operations_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         %{} = op <- Operations.get(company_id, id),
         {:ok, _} <- Operations.delete(op) do
      Respond.no_content(conn)
    else
      nil -> Respond.error(conn, {404, "операцията не е намерена"})
      error -> Respond.error(conn, error)
    end
  end

  def exemptions(conn, params) do
    items = Vat.exemptions(params["search"] || "")
    Respond.ok(conn, Render.page(items, params))
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} -> {:ok, company_id}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

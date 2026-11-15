defmodule BotyagaWeb.VatController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Vat}
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
         {:ok, file} <- Vat.export(company_id, params["period"] || "", params["type"] || "") do
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

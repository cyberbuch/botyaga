defmodule BotyagaWeb.SaftController do
  use BotyagaWeb, :controller

  import Plug.Conn

  alias Botyaga.{Companies, Saft}
  alias Botyaga.Saft.Mappings
  alias BotyagaWeb.Respond

  # Големите XML-и се изпращат поточно, на части (chunked), без един огромен отговор.
  def export(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, result} <- Saft.export_parts(company_id, params) do
      conn =
        conn
        |> put_resp_header("content-type", "application/xml; charset=utf-8")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{result.filename}\"")

      conn
      |> send_chunked(200)
      |> stream_parts(result.parts)
    else
      error -> Respond.error(conn, error)
    end
  end

  defp stream_parts(conn, parts) do
    conn =
      Enum.reduce_while(parts, conn, fn part, conn ->
        case Plug.Conn.chunk(conn, part) do
          {:ok, conn} -> {:cont, conn}
          {:error, _} -> {:halt, conn}
        end
      end)

    {:ok, conn} = Plug.Conn.chunk(conn, "")
    conn
  end

  # XML + списък от грешки/предупреждения (експортът продължава, но проблемите са видими).
  def preview(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, result} <- Saft.preview(company_id, params) do
      Respond.ok(conn, result)
    else
      error -> Respond.error(conn, error)
    end
  end

  def mappings_index(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Mappings.index(company_id, Map.get(params, "kind", "")) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def mappings_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Mappings.create(company_id, params) do
      Respond.ok(conn, data, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def mappings_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Mappings.update(company_id, id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def mappings_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Mappings.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def mappings_defaults(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Mappings.defaults(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} when company_id > 0 -> {:ok, company_id}
      {:ok, _} -> {:error, {422, "няма активна фирма за експорт"}}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

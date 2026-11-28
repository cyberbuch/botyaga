defmodule BotyagaWeb.AttachmentsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Attachments, Companies}
  alias BotyagaWeb.Respond

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, id} when id > 0 -> {:ok, id}
      _ -> {:error, {422, "няма активна фирма"}}
    end
  end

  def index(conn, %{"doc_type" => t, "doc_id" => id}) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{items: Attachments.list(cid, t, String.to_integer(id))})
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, %{"doc_type" => t, "doc_id" => id} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, a} <- Attachments.create(cid, t, String.to_integer(id), params["file"]) do
      Respond.ok(conn, a, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def download(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, a} <- Attachments.get(cid, id) do
      Respond.attachment(conn, a.data, a.content_type, a.filename)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, _} <- Attachments.delete(cid, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end
end

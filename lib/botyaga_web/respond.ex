defmodule BotyagaWeb.Respond do
  @moduledoc "Отговори: JSON с `detail` при грешка и статус по контракт."

  import Plug.Conn
  import Phoenix.Controller

  def ok(conn, data, status \\ 200) do
    conn |> put_status(status) |> json(data)
  end

  def no_content(conn), do: send_resp(conn, 204, "")

  def error(conn, {status, detail}) when is_binary(detail) do
    conn |> put_status(status) |> json(%{detail: detail})
  end

  def error(conn, {:error, {status, detail}}), do: error(conn, {status, detail})

  def error(conn, status, detail) when is_binary(detail), do: error(conn, {status, detail})
end

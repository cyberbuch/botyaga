defmodule TransportWeb.Plugs.Auth do
  @moduledoc "Иска валиден botyaga JWT; слага `current_sub` в assigns."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    token = bearer(conn)

    case Transport.Auth.decode(token) do
      {:ok, %{"sub" => sub}} -> assign(conn, :current_sub, sub)
      _ -> halt_error(conn, 401, "невалиден или липсващ токен")
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] ->
        case String.trim(value) do
          "Bearer " <> token -> String.trim(token)
          "bearer " <> token -> String.trim(token)
          _ -> ""
        end

      [] ->
        ""
    end
  end

  defp halt_error(conn, status, detail) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{detail: detail}))
    |> halt()
  end
end

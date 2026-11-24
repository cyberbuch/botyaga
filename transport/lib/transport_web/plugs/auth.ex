defmodule TransportWeb.Plugs.Auth do
  @moduledoc "Иска валиден botyaga JWT; слага `current_sub` и `current_ver` в assigns."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Transport.Auth.decode(bearer(conn)) do
      {:ok, %{"sub" => sub, "ver" => ver}} ->
        conn |> assign(:current_sub, sub) |> assign(:current_ver, ver)

      {:error, :unavailable} ->
        halt(conn, 503, "автентикацията е временно недостъпна")

      _ ->
        halt(conn, 401, "невалиден или изтекъл токен")
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

  def halt(conn, status, detail) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{detail: detail}))
    |> halt()
  end
end

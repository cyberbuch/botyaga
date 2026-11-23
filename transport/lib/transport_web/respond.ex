defmodule TransportWeb.Respond do
  @moduledoc "JSON отговори и обхват по фирма (заглавка `x-company-id`)."

  import Plug.Conn

  def ok(conn, data, status \\ 200) do
    conn |> put_status(status) |> Phoenix.Controller.json(data)
  end

  def error(conn, {status, detail}) when is_binary(detail) do
    conn |> put_status(status) |> Phoenix.Controller.json(%{detail: detail})
  end

  def error(conn, {:error, {status, detail}}), do: error(conn, {status, detail})

  def company_id(conn) do
    raw =
      case get_req_header(conn, "x-company-id") do
        [value | _] -> value
        [] -> conn.params["company_id"] || ""
      end

    case Integer.parse(to_string(raw)) do
      {n, _} -> n
      :error -> 0
    end
  end
end

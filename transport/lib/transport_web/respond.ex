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

  @doc "Фирмата от заглавката; всичко освен цяло положително число е 0 ( = отказ в Scope)."
  def company_id(conn) do
    case get_req_header(conn, "x-company-id") do
      [value | _] ->
        case Integer.parse(String.trim(value)) do
          {n, ""} when n > 0 -> n
          _ -> 0
        end

      [] ->
        0
    end
  end
end

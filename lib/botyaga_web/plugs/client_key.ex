defmodule BotyagaWeb.Plugs.ClientKey do
  @moduledoc "Ключ за лимита: верен токен дава кош по потребител, иначе по IP."

  alias Botyaga.Accounts

  def general(conn) do
    case bearer(conn) do
      "" ->
        {:ip, client_ip(conn)}

      token ->
        secret = Application.get_env(:botyaga, :jwt_secret)

        case Accounts.JWT.decode(secret, token) do
          {:ok, %{"sub" => sub}} -> {:user, sub}
          _ -> {:ip, client_ip(conn)}
        end
    end
  end

  def auth(conn), do: {:ip, client_ip(conn)}

  defp bearer(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
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

  @doc "Адресът на клиента: последното добавено в X-Forwarded-For, само от доверен прокси."
  def client_ip(conn) do
    peer = conn.remote_ip

    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] ->
        forwarded =
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> List.last()

        if trusted?(peer) and forwarded, do: forwarded, else: format_ip(peer)

      [] ->
        format_ip(peer)
    end
  end

  defp format_ip(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp trusted?({127, _, _, _}), do: true
  defp trusted?({10, _, _, _}), do: true
  defp trusted?({192, 168, _, _}), do: true
  defp trusted?({172, second, _, _}) when second in 16..31, do: true
  defp trusted?({169, 254, _, _}), do: true
  defp trusted?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp trusted?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  defp trusted?(_), do: false
end

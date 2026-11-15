defmodule BotyagaWeb.Plugs.RateLimitAuth do
  @moduledoc "Строг лимит за входа и регистрацията: 30 накуп и 2/сек на адрес."

  import Plug.Conn

  alias Botyaga.RateLimit

  def init(opts), do: opts

  def call(conn, _opts) do
    key = BotyagaWeb.Plugs.ClientKey.auth(conn)

    case RateLimit.check(key, 30, 2) do
      :allow -> conn
      {:deny, _retry} -> send_resp(conn, 429, "") |> halt()
    end
  end
end

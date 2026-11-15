defmodule BotyagaWeb.Plugs.RateLimitGeneral do
  @moduledoc "Общ лимит: 300 заявки накуп и 20/сек на потребител."

  import Plug.Conn

  alias Botyaga.RateLimit

  def init(opts), do: opts

  def call(conn, _opts) do
    key = BotyagaWeb.Plugs.ClientKey.general(conn)

    case RateLimit.check(key, 300, 20) do
      :allow -> conn
      {:deny, _retry} -> send_resp(conn, 429, "") |> halt()
    end
  end
end

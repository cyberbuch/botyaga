defmodule TransportWeb.HealthController do
  use TransportWeb, :controller

  def ready(conn, _params) do
    json(conn, %{status: "ok", service: "transport"})
  end
end

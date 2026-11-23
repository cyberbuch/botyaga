defmodule TransportWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :transport

  plug CORSPlug,
    origin:
      Application.compile_env(:transport, :cors_origins, [
        "http://localhost:3021",
        "http://127.0.0.1:3021"
      ]),
    methods: ["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
    headers: ["authorization", "content-type"]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug TransportWeb.Router
end

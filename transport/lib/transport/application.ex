defmodule Transport.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TransportWeb.Telemetry,
      Transport.Repo,
      {DNSCluster, query: Application.get_env(:transport, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Transport.PubSub},
      # Start a worker by calling: Transport.Worker.start_link(arg)
      # {Transport.Worker, arg},
      # Start to serve requests, typically the last entry
      TransportWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Transport.Supervisor]

    with {:ok, sup} <- Supervisor.start_link(children, opts) do
      if Application.get_env(:transport, :seed_destinations, true) do
        Transport.Destinations.seed()
      end

      {:ok, sup}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TransportWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

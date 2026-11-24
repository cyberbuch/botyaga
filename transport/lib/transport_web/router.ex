defmodule TransportWeb.Router do
  use TransportWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug TransportWeb.Plugs.Auth
    plug TransportWeb.Plugs.Scope
  end

  scope "/", TransportWeb do
    get "/ready", HealthController, :ready
  end

  scope "/v1", TransportWeb do
    pipe_through :api

    resources "/vehicles", VehicleController, except: [:new, :edit]
    resources "/drivers", DriverController, except: [:new, :edit]
    resources "/destinations", DestinationController, except: [:new, :edit]
    resources "/waybills", WaybillController, except: [:new, :edit]
    post "/waybills/:id/close", WaybillController, :close
    resources "/trips", TripController, except: [:new, :edit]
    post "/trips/:id/report", TripController, :report
  end
end

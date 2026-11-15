defmodule BotyagaWeb.HealthController do
  use BotyagaWeb, :controller

  alias Botyaga.Repo

  def health(conn, _params) do
    BotyagaWeb.Respond.ok(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> BotyagaWeb.Respond.ok(conn, %{status: "ok", database: "up"})
      {:error, error} -> BotyagaWeb.Respond.error(conn, {503, Exception.message(error)})
    end
  end
end

defmodule BotyagaWeb.RatesController do
  use BotyagaWeb, :controller

  alias Botyaga.Rates
  alias BotyagaWeb.Respond

  def index(conn, params) do
    with {:ok, data} <- Rates.index(params),
         do: Respond.ok(conn, data),
         else: (error -> Respond.error(conn, error))
  end

  def rate(conn, params) do
    with {:ok, data} <- Rates.rate_query(params),
         do: Respond.ok(conn, data),
         else: (error -> Respond.error(conn, error))
  end

  def cross(conn, params) do
    with {:ok, data} <- Rates.cross(params),
         do: Respond.ok(conn, data),
         else: (error -> Respond.error(conn, error))
  end

  def import(conn, params) do
    with {:ok, data} <- Rates.import(params),
         do: Respond.ok(conn, data),
         else: (error -> Respond.error(conn, error))
  end
end

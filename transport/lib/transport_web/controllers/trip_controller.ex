defmodule TransportWeb.TripController do
  use TransportWeb, :controller

  alias Transport.Trips
  alias TransportWeb.Respond

  def index(conn, _params) do
    Respond.ok(conn, %{items: Trips.list(Respond.company_id(conn))})
  end

  def show(conn, %{"id" => id}) do
    case Trips.get(Respond.company_id(conn), id) do
      nil -> Respond.error(conn, {404, "командировката не е намерена"})
      t -> Respond.ok(conn, Trips.json(t))
    end
  end

  def create(conn, params) do
    case Trips.create(Respond.company_id(conn), params) do
      {:ok, t} -> Respond.ok(conn, Trips.json(t), 201)
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, t} <- fetch(conn, id),
         {:ok, updated} <- Trips.update(t, params) do
      Respond.ok(conn, Trips.json(updated))
    else
      error -> Respond.error(conn, error)
    end
  end

  def report(conn, %{"id" => id}) do
    with {:ok, t} <- fetch(conn, id),
         {:ok, reported} <- Trips.report(t) do
      Respond.ok(conn, Trips.json(reported))
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    case fetch(conn, id) do
      {:ok, t} ->
        Trips.delete(t)
        Respond.ok(conn, %{ok: true})

      error ->
        Respond.error(conn, error)
    end
  end

  defp fetch(conn, id) do
    case Trips.get(Respond.company_id(conn), id) do
      nil -> {:error, {404, "командировката не е намерена"}}
      t -> {:ok, t}
    end
  end
end

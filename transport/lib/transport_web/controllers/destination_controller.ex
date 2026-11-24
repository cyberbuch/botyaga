defmodule TransportWeb.DestinationController do
  use TransportWeb, :controller

  alias Transport.Destinations
  alias TransportWeb.Respond

  def index(conn, params) do
    items = Destinations.list(params["kind"]) |> Enum.map(&Destinations.json/1)
    Respond.ok(conn, %{items: items})
  end

  def show(conn, %{"id" => id}) do
    case Destinations.get(id) do
      nil -> Respond.error(conn, {404, "дестинацията не е намерена"})
      d -> Respond.ok(conn, Destinations.json(d))
    end
  end

  def create(conn, params) do
    case Destinations.create(params) do
      {:ok, d} -> Respond.ok(conn, Destinations.json(d), 201)
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Destinations.get(id) do
      nil ->
        Respond.error(conn, {404, "дестинацията не е намерена"})

      d ->
        case Destinations.update(d, params) do
          {:ok, d} -> Respond.ok(conn, Destinations.json(d))
          error -> Respond.error(conn, error)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Destinations.get(id) do
      nil ->
        Respond.error(conn, {404, "дестинацията не е намерена"})

      d ->
        case Destinations.delete(d) do
          {:ok, _} -> Respond.ok(conn, %{ok: true})
          error -> Respond.error(conn, error)
        end
    end
  end
end

defmodule TransportWeb.VehicleController do
  use TransportWeb, :controller

  alias Transport.Vehicles
  alias TransportWeb.Respond

  def index(conn, _params) do
    cid = Respond.company_id(conn)
    Respond.ok(conn, %{items: Enum.map(Vehicles.list(cid), &Vehicles.json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Vehicles.get(Respond.company_id(conn), id) do
      nil -> Respond.error(conn, {404, "автомобилът не е намерен"})
      v -> Respond.ok(conn, Vehicles.json(v))
    end
  end

  def create(conn, params) do
    case Vehicles.create(Respond.company_id(conn), params) do
      {:ok, v} -> Respond.ok(conn, Vehicles.json(v), 201)
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Vehicles.get(Respond.company_id(conn), id) do
      nil ->
        Respond.error(conn, {404, "автомобилът не е намерен"})

      v ->
        case Vehicles.update(v, params) do
          {:ok, v} -> Respond.ok(conn, Vehicles.json(v))
          error -> Respond.error(conn, error)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Vehicles.get(Respond.company_id(conn), id) do
      nil ->
        Respond.error(conn, {404, "автомобилът не е намерен"})

      v ->
        case Vehicles.delete(v) do
          {:ok, _} -> Respond.ok(conn, %{ok: true})
          error -> Respond.error(conn, error)
        end
    end
  end
end

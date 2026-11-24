defmodule TransportWeb.DriverController do
  use TransportWeb, :controller

  alias Transport.Drivers
  alias TransportWeb.Respond

  def index(conn, _params) do
    cid = Respond.company_id(conn)
    Respond.ok(conn, %{items: Enum.map(Drivers.list(cid), &Drivers.json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Drivers.get(Respond.company_id(conn), id) do
      nil -> Respond.error(conn, {404, "шофьорът не е намерен"})
      d -> Respond.ok(conn, Drivers.json(d))
    end
  end

  def create(conn, params) do
    case Drivers.create(Respond.company_id(conn), params) do
      {:ok, d} -> Respond.ok(conn, Drivers.json(d), 201)
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Drivers.get(Respond.company_id(conn), id) do
      nil ->
        Respond.error(conn, {404, "шофьорът не е намерен"})

      d ->
        case Drivers.update(d, params) do
          {:ok, d} -> Respond.ok(conn, Drivers.json(d))
          error -> Respond.error(conn, error)
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Drivers.get(Respond.company_id(conn), id) do
      nil ->
        Respond.error(conn, {404, "шофьорът не е намерен"})

      d ->
        case Drivers.delete(d) do
          {:ok, _} -> Respond.ok(conn, %{ok: true})
          error -> Respond.error(conn, error)
        end
    end
  end
end

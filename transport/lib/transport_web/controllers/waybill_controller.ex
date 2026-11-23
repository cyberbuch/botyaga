defmodule TransportWeb.WaybillController do
  use TransportWeb, :controller

  alias Transport.Waybills
  alias TransportWeb.Respond

  def index(conn, _params) do
    Respond.ok(conn, %{items: Waybills.list(Respond.company_id(conn))})
  end

  def show(conn, %{"id" => id}) do
    case Waybills.get(Respond.company_id(conn), id) do
      nil -> Respond.error(conn, {404, "пътният лист не е намерен"})
      w -> Respond.ok(conn, w)
    end
  end

  def create(conn, params) do
    case Waybills.create(Respond.company_id(conn), params) do
      {:ok, w} -> Respond.ok(conn, w, 201)
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, w} <- fetch(conn, id),
         {:ok, updated} <- Waybills.update(w, params) do
      Respond.ok(conn, updated)
    else
      error -> Respond.error(conn, error)
    end
  end

  def close(conn, %{"id" => id} = params) do
    with {:ok, w} <- fetch(conn, id),
         {:ok, closed} <- Waybills.close(w, params) do
      Respond.ok(conn, closed)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Waybills.fetch(Respond.company_id(conn), id) do
      nil ->
        Respond.error(conn, {404, "пътният лист не е намерен"})

      w ->
        Waybills.delete(w)
        Respond.ok(conn, %{ok: true})
    end
  end

  defp fetch(conn, id) do
    case Waybills.fetch(Respond.company_id(conn), id) do
      nil -> {:error, {404, "пътният лист не е намерен"}}
      w -> {:ok, w}
    end
  end
end

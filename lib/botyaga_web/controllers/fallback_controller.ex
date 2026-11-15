defmodule BotyagaWeb.FallbackController do
  use BotyagaWeb, :controller

  alias BotyagaWeb.Respond

  @doc "GET без маршрут връща празен списък, останалите методи — 404."
  def fallback(conn, _params) do
    if conn.method == "GET" do
      Respond.ok(conn, %{items: [], count: 0, total: 0, limit: 50, offset: 0, has_more: false})
    else
      Respond.error(conn, {404, "Not Found"})
    end
  end
end

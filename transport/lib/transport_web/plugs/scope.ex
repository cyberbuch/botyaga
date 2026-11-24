defmodule TransportWeb.Plugs.Scope do
  @moduledoc """
  Фирмата от `x-company-id` се взима на доверие едва след като botyaga потвърди,
  че потребителят е активен, с текущата версия на сесията си и член на фирмата.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    company_id = TransportWeb.Respond.company_id(conn)

    case access().check(conn.assigns.current_sub, conn.assigns.current_ver, company_id) do
      :ok ->
        assign(conn, :company_id, company_id)

      {:error, {status, detail}} ->
        TransportWeb.Plugs.Auth.halt(conn, status, detail)

      {:error, _} ->
        TransportWeb.Plugs.Auth.halt(conn, 503, "автентикацията е временно недостъпна")
    end
  end

  defp access, do: Application.get_env(:transport, :access, Transport.Botyaga)
end

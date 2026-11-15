defmodule BotyagaWeb.AuthFlowController do
  use BotyagaWeb, :controller

  alias Botyaga.Registration
  alias BotyagaWeb.Respond

  def registration_status(conn, _params) do
    Respond.ok(conn, %{
      ok: 1,
      registration_enabled: if(Registration.registration_enabled?(), do: 1, else: 0)
    })
  end

  def register(conn, params) do
    case Registration.register(params) do
      {:ok, %{company_id: nil}} ->
        answer(conn, nil)

      {:ok, %{company_id: company_id}} ->
        answer(conn, company_id)

      {:error, {status, detail}} ->
        Respond.error(conn, {status, detail})
    end
  end

  def forgot_password(conn, params) do
    case Registration.forgot_password(params) do
      {:ok, %{message: message}} -> Respond.ok(conn, %{ok: 1, message: message})
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
    end
  end

  def reset_password(conn, params) do
    case Registration.reset_password(params) do
      {:ok, %{message: message}} -> Respond.ok(conn, %{ok: 1, message: message})
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
    end
  end

  # Един и същ отговор при свободен и при зает имейл.
  defp answer(conn, company_id) do
    Respond.ok(
      conn,
      %{
        ok: 1,
        company_id: company_id,
        message: "Регистрацията е приета. Ако email-ът е свободен, вече можете да влезете."
      },
      201
    )
  end
end

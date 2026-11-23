defmodule BotyagaWeb.AdminController do
  @moduledoc "Админ панел: матрица потребители × фирми × роли, лог за сесиите, прекратяване."

  use BotyagaWeb, :controller

  alias Botyaga.{Access, Accounts, Accounts.LoginLog, Companies, Stamp}
  alias BotyagaWeb.{Render, Respond}

  def access(conn, _params) do
    with :ok <- require_super(conn) do
      by_user = Access.all_memberships() |> Enum.group_by(& &1.user_id)

      users =
        Access.users_index()
        |> Enum.map(fn u ->
          memberships =
            Map.get(by_user, u.id, [])
            |> Enum.map(&Render.membership/1)

          u |> Render.user() |> Map.put(:memberships, memberships)
        end)

      companies =
        Companies.index_for(conn.assigns.current_user)
        |> Enum.map(&%{id: &1.id, name: &1.name})

      Respond.ok(conn, %{
        users: users,
        roles: Enum.map(Access.roles_index(), &Render.role/1),
        companies: companies
      })
    else
      error -> Respond.error(conn, error)
    end
  end

  def login_events(conn, params) do
    with :ok <- require_super(conn) do
      LoginLog.index(params)
      |> Enum.map(&event_json/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def revoke_sessions(conn, %{"id" => id}) do
    with :ok <- require_super(conn),
         {:ok, user} <- find_user(id) do
      Accounts.bump_version(user.id)
      LoginLog.record(conn, "sessions_revoked", user.username, user.id, "от администратор")
      Respond.ok(conn, %{ok: true, session_version: user.session_version + 1})
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Вътрешни

  defp event_json(e) do
    %{
      id: e.id,
      user_id: e.user_id,
      user_login: e.user_login,
      event: e.event,
      ip: e.ip,
      user_agent: e.user_agent,
      detail: e.detail,
      created_at: Stamp.to_stamp(e.created_at)
    }
  end

  defp require_super(conn) do
    case Access.require_super_admin(conn.assigns.current_user) do
      :ok -> :ok
      {:error, :forbidden} -> {:error, {403, "изисква се супер администратор"}}
    end
  end

  defp find_user(id) do
    case Accounts.get_by_id(to_integer(id)) do
      nil -> {:error, {404, "потребителят не е намерен"}}
      user -> {:ok, user}
    end
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

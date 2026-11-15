defmodule BotyagaWeb.AccessController do
  use BotyagaWeb, :controller

  alias Botyaga.{Access, Accounts}
  alias BotyagaWeb.{Render, Respond}

  def users_index(conn, params) do
    with :ok <- require_super(conn) do
      Access.users_index()
      |> Enum.map(&Render.user/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def users_create(conn, params) do
    with :ok <- require_super(conn) do
      case Access.create_user(params) do
        {:ok, user} -> user |> Render.user() |> then(&Respond.ok(conn, &1, 201))
        {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      end
    end
  end

  def users_update(conn, %{"id" => id} = params) do
    with :ok <- require_super(conn),
         {:ok, user} <- find_user(id) do
      case Access.update_user(user, params) do
        {:ok, user} -> user |> Render.user() |> then(&Respond.ok(conn, &1))
        {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      end
    end
  end

  def users_delete(conn, %{"id" => id}) do
    with :ok <- require_super(conn),
         {:ok, user} <- find_user(id),
         :ok <- not_self(conn, user) do
      case Access.delete_user(user) do
        {:ok, nil} -> Respond.no_content(conn)
        {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      end
    end
  end

  def roles_index(conn, params) do
    with :ok <- require_super(conn) do
      Access.roles_index()
      |> Enum.map(&Render.role/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def roles_create(conn, params) do
    with :ok <- require_super(conn) do
      case Access.create_role(params) do
        {:ok, role} -> role |> Render.role() |> then(&Respond.ok(conn, &1, 201))
        {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      end
    end
  end

  def roles_update(conn, %{"id" => id} = params) do
    with :ok <- require_super(conn),
         {:ok, role} <- find_role(id) do
      case Access.update_role(role, params) do
        {:ok, role} -> role |> Render.role() |> then(&Respond.ok(conn, &1))
        {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      end
    end
  end

  def roles_delete(conn, %{"id" => id}) do
    with :ok <- require_super(conn),
         {:ok, role} <- find_role(id) do
      Access.delete_role(role)
      Respond.no_content(conn)
    end
  end

  ## Вътрешни

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

  defp find_role(id) do
    case Access.get_role(to_integer(id)) do
      nil -> {:error, {404, "ролята не е намерена"}}
      role -> {:ok, role}
    end
  end

  defp not_self(conn, user) do
    if conn.assigns.current_user.username == user.username,
      do: {:error, {422, "не може да изтриете собствения си потребител"}},
      else: :ok
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

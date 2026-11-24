defmodule BotyagaWeb.MembersController do
  use BotyagaWeb, :controller

  import Ecto.Query

  alias Botyaga.{Access, Accounts, Params, Repo}
  alias Botyaga.Access.Membership
  alias BotyagaWeb.{Render, Respond}

  def index(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- scope(conn, company_id) do
      page = Render.page(members_of(company_id), params)
      Respond.ok(conn, Map.put(page, :roles, roles()))
    else
      error -> Respond.error(conn, error)
    end
  end

  def add(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- scope(conn, company_id),
         {:ok, email} <- required_email(params),
         {:ok, role_id} <- resolve_role(params),
         {:ok, user} <- find_or_create_user(params, email) do
      Access.grant(user.id, company_id, role_id)
      Respond.ok(conn, member_of(company_id, user.id), 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => company_id, "user_id" => user_id} = params) do
    with {:ok, company_id} <- scope(conn, company_id),
         {:ok, role_id} <- resolve_role(params),
         {:ok, user_id} <- existing_membership(company_id, user_id) do
      Access.grant(user_id, company_id, role_id)
      Respond.ok(conn, member_of(company_id, user_id))
    else
      error -> Respond.error(conn, error)
    end
  end

  def remove(conn, %{"id" => company_id, "user_id" => user_id}) do
    with {:ok, company_id} <- scope(conn, company_id),
         :ok <- not_self(conn, to_integer(user_id)),
         {:ok, user_id} <- existing_membership(company_id, user_id),
         :ok <- not_last_membership(user_id) do
      Access.revoke(user_id, company_id)
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Вътрешни

  # Без последната фирма потребителят остава без достъп до нищо — отказва се.
  defp not_last_membership(user_id) do
    user = Repo.get(Accounts.User, user_id)

    if user.is_super_admin == 1 or length(Access.memberships_of(user_id)) > 1,
      do: :ok,
      else: {:error, {422, "потребителят трябва да остане обвързан с поне една фирма"}}
  end

  defp scope(conn, company_id) do
    case Access.company_scope(conn.assigns.current_user, to_integer(company_id)) do
      {:ok, id} -> {:ok, id}
      {:error, :not_found} -> {:error, {404, "фирмата не е намерена"}}
      {:error, :forbidden_users} -> {:error, {403, "липсва право: users"}}
    end
  end

  defp members_of(company_id) do
    query =
      from(m in Membership,
        left_join: u in Accounts.User,
        on: m.user_id == u.id,
        left_join: r in Access.Role,
        on: m.role_id == r.id,
        where: m.company_id == ^company_id,
        order_by: [asc: u.name],
        select: {m, u, r}
      )

    query
    |> Repo.all()
    |> Enum.map(fn {m, u, r} -> Render.member(m, u, r && r.name) end)
  end

  defp member_of(company_id, user_id) do
    membership =
      Repo.one(
        from(m in Membership, where: m.company_id == ^company_id and m.user_id == ^user_id)
      )

    user = Repo.get(Accounts.User, user_id)
    role = if membership.role_id, do: Access.get_role(membership.role_id), else: nil
    Render.member(membership, user, role && role.name)
  end

  defp existing_membership(company_id, user_id) do
    user_id = to_integer(user_id)

    case Access.membership_role(user_id, company_id) do
      nil -> {:error, {404, "потребителят не е във фирмата"}}
      _role -> {:ok, user_id}
    end
  end

  defp not_self(conn, user_id) do
    if conn.assigns.current_user.id == user_id,
      do: {:error, {422, "не може да махнете себе си от фирмата"}},
      else: :ok
  end

  defp required_email(params) do
    case Params.str(params, "email") do
      {:present, value} ->
        value = String.trim(value)
        if value == "", do: {:error, {422, "email е задължителен"}}, else: {:ok, value}

      _ ->
        {:error, {422, "email е задължителен"}}
    end
  end

  defp find_or_create_user(params, email) do
    case Accounts.get_by_login(email) do
      nil -> create_user(params, email)
      user -> {:ok, user}
    end
  end

  defp create_user(params, email) do
    name =
      case Params.str(params, "name") do
        {:present, value} -> String.trim(value)
        _ -> ""
      end

    password =
      case Params.str(params, "password") do
        {:present, value} -> value
        _ -> ""
      end

    cond do
      name == "" ->
        {:error, {422, "name е задължително"}}

      byte_size(password) < 8 ->
        {:error, {422, "паролата трябва да е поне 8 символа"}}

      true ->
        case Accounts.create_user(email, name, password, "user") do
          {:ok, user} -> {:ok, user}
          {:error, :email_taken} -> {:error, {409, "имейлът вече се ползва"}}
        end
    end
  end

  defp resolve_role(params) do
    case Params.integer(params, "role_id") do
      nil ->
        resolve_role_by_name(params)

      {:error, message} ->
        {:error, {422, message}}

      role_id ->
        if role_id > 0 and Access.get_role(role_id) != nil do
          {:ok, role_id}
        else
          {:error, {422, "ролята не е намерена"}}
        end
    end
  end

  defp resolve_role_by_name(params) do
    name =
      case Params.str(params, "role") do
        {:present, value} -> String.trim(value)
        _ -> ""
      end

    name = if name == "", do: Access.role_accountant(), else: name

    case Access.role_id_by_name(name) do
      {:ok, id} -> {:ok, id}
      {:error, _} -> {:error, {422, "ролята не е намерена"}}
    end
  end

  defp roles do
    Enum.map(Access.roles_index(), fn role ->
      %{id: role.id, name: role.name, description: role.description}
    end)
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

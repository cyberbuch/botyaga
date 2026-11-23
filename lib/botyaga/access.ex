defmodule Botyaga.Access do
  @moduledoc """
  Потребители и роли. Членството дава роля, ролята дава права само в
  рамките на активната фирма. Супер администраторът минава навсякъде.
  """

  import Ecto.Query

  alias Botyaga.Stamp
  alias Botyaga.{Accounts, Params, Repo}
  alias Botyaga.Access.{Role, Membership}

  @role_admin "Администратор на фирма"
  @role_accountant "Счетоводител"
  @role_facturist "Фактурист"

  @admin_perms ~w(companies accounts counterparts products invoices scans journal periods vat
                   banking assets stock production dividends reports saft users rates)
  @accountant_perms ~w(companies accounts counterparts products invoices scans journal periods vat
                        banking assets stock production dividends reports saft rates)
  @facturist_perms ~w(invoices counterparts products scans)

  def role_admin, do: @role_admin
  def role_accountant, do: @role_accountant

  @doc "Трите роли на фирма се създават при старт, ако липсват."
  def ensure_roles do
    seed([
      {@role_admin, "Пълен достъп до данните на фирмата, включително нейните потребители",
       @admin_perms},
      {@role_accountant, "Счетоводни модули на фирмата без управление на потребители",
       @accountant_perms},
      {@role_facturist, "Фактури, контрагенти и стоки на фирмата", @facturist_perms}
    ])
  end

  defp seed(roles) do
    Enum.each(roles, fn {name, description, perms} ->
      if Repo.get_by(Role, name: name) == nil do
        Repo.insert!(%Role{
          name: name,
          description: description,
          permissions: Jason.encode!(perms),
          created_at: Stamp.now()
        })
      end
    end)
  end

  def role_id_by_name(name) do
    case Repo.get_by(Role, name: name) do
      %Role{id: id} -> {:ok, id}
      nil -> {:error, :missing}
    end
  end

  def get_role(role_id), do: Repo.get(Role, role_id)

  @doc "Правата на роля като списък от низове."
  def role_permissions(nil), do: []

  def role_permissions(role_id) do
    case get_role(role_id) do
      %Role{permissions: raw} -> decode_perms(raw)
      nil -> []
    end
  end

  def decode_perms(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  def decode_perms(_), do: []

  @doc "Правата на потребителя спрямо дадена фирма."
  def perms_for(%Accounts.User{is_super_admin: 1}, _company_id), do: ["*"]

  def perms_for(%Accounts.User{id: user_id}, company_id) do
    case membership_role(user_id, company_id) do
      nil -> []
      role_id -> role_permissions(role_id)
    end
  end

  def allowed?(_perms, _key, is_super_admin: 1), do: true

  def allowed?(perms, key, is_super_admin: _) do
    Enum.any?(perms, &(&1 == "*" or &1 == key))
  end

  def membership_role(user_id, company_id) do
    case Repo.get_by(Membership, user_id: user_id, company_id: company_id) do
      %Membership{role_id: role_id} -> role_id
      nil -> nil
    end
  end

  def grant(user_id, company_id, role_id) do
    case Repo.get_by(Membership, user_id: user_id, company_id: company_id) do
      %Membership{} = membership ->
        membership
        |> Ecto.Changeset.change(role_id: role_id)
        |> Repo.update!()

      nil ->
        Repo.insert!(%Membership{
          user_id: user_id,
          company_id: company_id,
          role_id: role_id,
          created_at: Stamp.now()
        })
    end
  end

  def revoke(user_id, company_id) do
    Repo.delete_all(
      from(m in Membership, where: m.user_id == ^user_id and m.company_id == ^company_id)
    )
  end

  def company_ids_of(user_id) do
    Repo.all(
      from(m in Membership,
        where: m.user_id == ^user_id,
        order_by: [asc: m.company_id],
        select: m.company_id
      )
    )
  end

  def memberships_of(user_id) do
    query =
      from(m in Membership,
        left_join: r in Role,
        on: m.role_id == r.id,
        left_join: c in Botyaga.Companies.Company,
        on: m.company_id == c.id,
        where: m.user_id == ^user_id,
        order_by: [asc: m.company_id],
        select: {m, r, c}
      )

    Repo.all(query)
    |> Enum.map(fn {m, r, c} ->
      %{
        company_id: m.company_id,
        role_id: m.role_id,
        role: r && r.name,
        company_name: c && c.name
      }
    end)
  end

  def super_count,
    do: Repo.aggregate(from(u in Accounts.User, where: u.is_super_admin == 1), :count, :id)

  @doc "Всички членства с име на фирма и роля — за админ матрицата."
  def all_memberships do
    Repo.all(
      from(m in Membership,
        left_join: r in Role,
        on: m.role_id == r.id,
        left_join: c in Botyaga.Companies.Company,
        on: m.company_id == c.id,
        order_by: [asc: m.user_id, asc: m.company_id],
        select: {m, r, c}
      )
    )
    |> Enum.map(fn {m, r, c} ->
      %{
        user_id: m.user_id,
        company_id: m.company_id,
        company_name: c && c.name,
        role_id: m.role_id,
        role: r && r.name
      }
    end)
  end

  @doc "Съществуващите потребители получават администраторска роля във всички фирми."
  def backfill do
    with {:ok, admin_id} <- role_id_by_name(@role_admin),
         user_ids when user_ids != [] <-
           Repo.all(from(u in Accounts.User, where: u.is_super_admin == 0, select: u.id)),
         company_ids when company_ids != [] <-
           Repo.all(from(c in Botyaga.Companies.Company, select: c.id)) do
      for user_id <- user_ids, company_id <- company_ids do
        if membership_role(user_id, company_id) == nil do
          grant(user_id, company_id, admin_id)
        end
      end
    else
      _ -> :ok
    end

    :ok
  end

  def require_super_admin(%Accounts.User{is_super_admin: 1}), do: :ok
  def require_super_admin(_), do: {:error, :forbidden}

  @doc """
  Достъп до фирма за управление на нейните потребители: супер администратор
  или администратор на активната фирма.
  """
  def company_scope(user, company_id) do
    cond do
      user.is_super_admin == 1 ->
        if Repo.get(Botyaga.Companies.Company, company_id),
          do: {:ok, company_id},
          else: {:error, :not_found}

      true ->
        with {:ok, active} <- Botyaga.Companies.resolve_active(user.username),
             true <- active == company_id do
          if allowed?(perms_for(user, company_id), "users", is_super_admin: user.is_super_admin) do
            {:ok, company_id}
          else
            {:error, :forbidden_users}
          end
        else
          _ -> {:error, :not_found}
        end
    end
  end

  ## Глобални потребители и роли (само супер администратор)

  def users_index do
    Repo.all(from(u in Accounts.User, order_by: [asc: u.name]))
  end

  def roles_index do
    Repo.all(from(r in Role, order_by: [asc: r.name]))
  end

  def create_user(params) do
    with {:ok, email} <- required_string(params, "email"),
         {:ok, name} <- required_string(params, "name"),
         {:ok, password} <- required_password(params["password"]) do
      if Accounts.email_taken?(email) do
        {:error, {409, "имейлът вече се ползва"}}
      else
        is_super = Params.flag(params, "is_super_admin") || 0
        memberships = parse_memberships(params)

        with :ok <- check_memberships(is_super, memberships) do
          user =
            Accounts.create_user(
              email,
              name,
              password,
              string_or(params, "role", "user"),
              is_active: Params.flag(params, "is_active") || 1,
              is_super_admin: is_super,
              role_id: Params.integer(params, "role_id") || 0
            )
            |> elem(1)

          sync_memberships(user.id, memberships, is_super)
          {:ok, user}
        end
      end
    end
  end

  def update_user(user, params) do
    email = optional_string(params, "email")
    password = optional_string(params, "password")
    next_super = Params.flag(params, "is_super_admin") || user.is_super_admin
    given? = memberships_given?(params)
    memberships = if given?, do: parse_memberships(params), else: existing_memberships(user.id)

    with :ok <- check_email_change(user, email, password),
         :ok <- check_password_length(password),
         :ok <- check_last_super_admin(user, params),
         :ok <- check_memberships(next_super, memberships) do
      Repo.transaction(fn ->
        changes = %{
          name: optional_string(params, "name") || user.name,
          role: optional_string(params, "role") || user.role,
          is_active: Params.flag(params, "is_active") || user.is_active,
          is_super_admin: next_super,
          role_id: Params.integer(params, "role_id") || user.role_id
        }

        updated = Repo.update!(Ecto.Changeset.change(user, changes))

        if password do
          Accounts.set_email(
            Repo.get!(Accounts.User, user.id),
            String.trim(email || updated.email),
            password
          )
        end

        if given?, do: sync_memberships(user.id, memberships, next_super)
        :ok
      end)

      {:ok, Repo.get(Accounts.User, user.id)}
    end
  end

  # Всеки потребител освен суперадминистратор трябва да е обвързан с фирма и роля.
  defp check_memberships(1, _), do: :ok

  defp check_memberships(_, []),
    do: {:error, {422, "потребителят трябва да е обвързан с поне една фирма и роля"}}

  defp check_memberships(_, list) do
    Enum.reduce_while(list, :ok, fn m, _ ->
      cond do
        Repo.get(Botyaga.Companies.Company, m.company_id) == nil ->
          {:halt, {:error, {422, "фирмата не е намерена"}}}

        get_role(m.role_id) == nil ->
          {:halt, {:error, {422, "ролята не е намерена"}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp sync_memberships(_user_id, _memberships, 1), do: :ok

  defp sync_memberships(user_id, memberships, _) do
    wanted = Enum.map(memberships, & &1.company_id)
    for cid <- company_ids_of(user_id), cid not in wanted, do: revoke(user_id, cid)
    for m <- memberships, do: grant(user_id, m.company_id, m.role_id)
    :ok
  end

  defp memberships_given?(params),
    do: Map.has_key?(params, "memberships") or Map.has_key?(params, :memberships)

  defp parse_memberships(params) do
    raw = Map.get(params, "memberships") || Map.get(params, :memberships) || []

    if is_list(raw) do
      raw
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn m ->
        %{
          company_id: Params.id(Map.get(m, "company_id") || Map.get(m, :company_id)),
          role_id: Params.id(Map.get(m, "role_id") || Map.get(m, :role_id))
        }
      end)
      |> Enum.filter(&(&1.company_id > 0 and &1.role_id > 0))
      |> Enum.uniq_by(& &1.company_id)
    else
      []
    end
  end

  defp existing_memberships(user_id) do
    Repo.all(
      from(m in Membership,
        where: m.user_id == ^user_id,
        select: %{company_id: m.company_id, role_id: m.role_id}
      )
    )
  end

  def delete_user(user) do
    if user.is_super_admin == 1 and super_count() <= 1 do
      {:error, {422, "последният супер администратор не може да се изтрие"}}
    else
      Accounts.delete_user(user)
      {:ok, nil}
    end
  end

  def create_role(params) do
    with {:ok, name} <- required_string(params, "name") do
      perms = decode_perms_param(params["permissions"] || params[:permissions])

      role = %Role{
        name: name,
        description: optional_string(params, "description"),
        permissions: Jason.encode!(perms),
        created_at: Stamp.now()
      }

      {:ok, Repo.insert!(role)}
    end
  end

  def update_role(role, params) do
    with {:ok, _name} <- check_role_name(params, role) do
      changes =
        Ecto.Changeset.change(role,
          name: optional_string(params, "name") || role.name,
          description: optional_string(params, "description") || role.description
        )

      changes =
        if params["permissions"] || params[:permissions] do
          Ecto.Changeset.change(changes,
            permissions:
              Jason.encode!(decode_perms_param(params["permissions"] || params[:permissions]))
          )
        else
          changes
        end

      {:ok, Repo.update!(changes)}
    end
  end

  def delete_role(role), do: Repo.delete(role)

  defp check_role_name(params, role) do
    case optional_string(params, "name") do
      nil ->
        {:ok, role.name}

      name ->
        if String.trim(name) == "",
          do: {:error, {422, "name е задължително"}},
          else: {:ok, String.trim(name)}
    end
  end

  defp required_string(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, String.trim(value)}

      {:error, _} ->
        {:error, {422, "#{key} трябва да е низ"}}

      :absent ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp optional_string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> String.trim(value)
      _ -> nil
    end
  end

  defp string_or(params, key, default) do
    case Params.str(params, key) do
      {:present, value} -> if String.trim(value) == "", do: default, else: String.trim(value)
      _ -> default
    end
  end

  defp required_password(nil), do: {:error, {422, "password е задължителен"}}
  defp required_password(""), do: {:error, {422, "password е задължителен"}}

  defp required_password(password) do
    if byte_size(password) < 8,
      do: {:error, {422, "паролата трябва да е поне 8 символа"}},
      else: {:ok, password}
  end

  defp check_email_change(_user, nil, _password), do: :ok

  defp check_email_change(user, email, password) do
    email = String.trim(email)

    cond do
      email == user.email -> :ok
      is_nil(password) -> {:error, {422, "при смяна на имейл подайте нова парола"}}
      Accounts.email_taken?(email, user.id) -> {:error, {409, "имейлът вече се ползва"}}
      true -> :ok
    end
  end

  defp check_password_length(nil), do: :ok

  defp check_password_length(password) do
    if byte_size(password) < 8,
      do: {:error, {422, "паролата трябва да е поне 8 символа"}},
      else: :ok
  end

  defp check_last_super_admin(user, params) do
    next_super = Params.flag(params, "is_super_admin") || user.is_super_admin

    if user.is_super_admin == 1 and next_super == 0 and super_count() <= 1 do
      {:error, {422, "последният супер администратор не може да се махне"}}
    else
      :ok
    end
  end

  defp decode_perms_param(nil), do: []

  defp decode_perms_param(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(fn s -> s |> to_string() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
  end

  defp decode_perms_param(other) when is_binary(other) do
    decode_perms(other)
  end

  defp decode_perms_param(_), do: []
end

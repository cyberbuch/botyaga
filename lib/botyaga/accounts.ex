defmodule Botyaga.Accounts do
  @moduledoc """
  Потребители: вход, пароли (argon2id с наследен sha256), сесийна версия,
  2FA и резервни кодове.
  """

  import Ecto.Query

  alias Botyaga.Stamp
  alias Botyaga.Repo
  alias Botyaga.Accounts.{User, RecoveryCode, PasswordResetToken, Totp}
  alias Botyaga.Settings

  def get_by_id(id), do: Repo.get(User, id)

  def get_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_by_email!(email) when is_binary(email) do
    Repo.get_by!(User, email: email)
  end

  @doc "Потребител по име за вход или по имейл — и двете влизат."
  def get_by_login(login) when is_binary(login) do
    case Repo.get_by(User, username: login) do
      %User{} = user -> user
      nil -> get_by_email(login)
    end
  end

  def user_count, do: Repo.aggregate(User, :count, :id)

  def is_super?(nil), do: false

  def is_super?(login) when is_binary(login) do
    case get_by_login(login) do
      %User{is_super_admin: 1} -> true
      _ -> false
    end
  end

  def email_taken?(email, except_id \\ 0) do
    query =
      from(u in User,
        where: (u.email == ^email or u.username == ^email) and u.id != ^except_id,
        select: u.id,
        limit: 1
      )

    Repo.one(query) != nil
  end

  @doc "Суперадминистратор само при празна база. Паролата никога не е фиксирана в кода."
  def provision_superadmin(password) do
    if user_count() == 0 and get_by_email("superadmin") == nil do
      create_user("superadmin", "Superadmin", password, "super_admin", is_super_admin: 1)
    else
      {:ok, nil}
    end
  end

  def create_user(email, name, password, role \\ "user", opts \\ []) do
    if email_taken?(email) do
      {:error, :email_taken}
    else
      hash = hash_password!(password)

      user = %User{
        email: email,
        name: name,
        username: email,
        password_hash: hash,
        role: role,
        is_active: Keyword.get(opts, :is_active, 1),
        is_super_admin: Keyword.get(opts, :is_super_admin, 0),
        role_id: Keyword.get(opts, :role_id, 0),
        created_at: Stamp.now()
      }

      {:ok, Repo.insert!(user)}
    end
  end

  @doc """
  Проверка на парола. `:rehash` е старият sha256 хеш — паролата е вярна,
  но трябва да се запише с argon2.
  """
  def authenticate(login, password) do
    case get_by_login(login) do
      nil ->
        burn_password_check(password)
        :error

      user ->
        case check_password(user.password_hash, user.email, password) do
          :ok -> {:ok, user}
          :rehash -> {:rehash, user}
          :fail -> :error
        end
    end
  end

  def check_password(stored, email, password) do
    cond do
      is_binary(stored) and String.starts_with?(stored, "$argon2") ->
        if Argon2.verify_pass(password, stored), do: :ok, else: :fail

      stored == legacy_hash(email, password) ->
        :rehash

      true ->
        :fail
    end
  end

  def password_ok?(nil, _password), do: false

  def password_ok?(user, password) do
    check_password(user.password_hash, user.email, password) != :fail
  end

  def hash_password!(password), do: Argon2.hash_pwd_salt(password)

  def burn_password_check(_password) do
    hash = :persistent_term.get(:botyaga_burn_hash, nil)

    hash =
      case hash do
        nil ->
          generated = Argon2.hash_pwd_salt("burn-only")
          :persistent_term.put(:botyaga_burn_hash, generated)
          generated

        hash ->
          hash
      end

    Argon2.verify_pass("probing", hash)
    :ok
  end

  defp legacy_hash(email, password) do
    :crypto.hash(:sha256, "bagabuch|#{email}|#{password}")
    |> Base.encode16(case: :lower)
  end

  @doc "Нова парола и нова версия на сесията — старите токени отпадат."
  def set_password(user, password) do
    hash = hash_password!(password)

    Repo.transaction(fn ->
      user
      |> Ecto.Changeset.change(password_hash: hash)
      |> Repo.update!()

      from(t in PasswordResetToken, where: t.user_id == ^user.id and t.used == 0)
      |> Repo.update_all(set: [used: 1])

      bump_version(user.id)
    end)
  end

  def rehash_password(user, password) do
    user
    |> Ecto.Changeset.change(password_hash: hash_password!(password))
    |> Repo.update!()
  end

  def bump_version(user_id) do
    version = (get_by_id(user_id).session_version || 0) + 1
    Repo.update_all(from(u in User, where: u.id == ^user_id), set: [session_version: version])
    version
  end

  def set_email(user, email, password) do
    hash = hash_password!(password)

    Repo.transaction(fn ->
      user
      |> Ecto.Changeset.change(email: email, password_hash: hash)
      |> Repo.update!()

      bump_version(user.id)
    end)
  end

  def set_name(user, name) do
    user
    |> Ecto.Changeset.change(name: name)
    |> Repo.update!()
  end

  def set_totp(user, enabled, secret, pending) do
    user
    |> Ecto.Changeset.change(
      totp_enabled: enabled,
      totp_secret_b32: secret,
      totp_pending_b32: pending
    )
    |> Repo.update!()
  end

  def mfa_failure(user) do
    fails = (user.mfa_fails || 0) + 1
    user |> Ecto.Changeset.change(mfa_fails: fails) |> Repo.update!()
    fails
  end

  def mfa_lock(user, until_unix) do
    user
    |> Ecto.Changeset.change(mfa_fails: 0, mfa_lock_until: until_unix)
    |> Repo.update!()
  end

  def mfa_reset(user) do
    user
    |> Ecto.Changeset.change(mfa_fails: 0, mfa_lock_until: 0)
    |> Repo.update!()
  end

  @doc "Консумира TOTP прозореца — едно и също код не минава повторно."
  def totp_consume_counter(user_id, counter) do
    key = "totp_last:#{user_id}"
    last = Settings.get(key) |> to_int()

    if counter > last do
      Settings.upsert(key, to_string(counter))
      true
    else
      false
    end
  end

  def wipe_recovery(user_id) do
    Repo.delete_all(from(c in RecoveryCode, where: c.user_id == ^user_id))
  end

  def insert_recovery(user_id, hashes) do
    Enum.each(hashes, fn hash ->
      Repo.insert!(%RecoveryCode{user_id: user_id, code_hash: hash})
    end)
  end

  @doc "Резервният код е за едно ползване: `used = 0` в условието предотвратява състезание."
  def take_recovery(user_id, code) do
    hash = Totp.recovery_hash(code)

    if hash == "" do
      false
    else
      query =
        from(c in RecoveryCode,
          where: c.user_id == ^user_id and c.code_hash == ^hash and c.used == 0,
          select: c.id,
          limit: 1
        )

      case Repo.one(query) do
        nil ->
          false

        id ->
          Repo.update_all(from(c in RecoveryCode, where: c.id == ^id and c.used == 0),
            set: [used: 1]
          ) > 0
      end
    end
  end

  def delete_user(user) do
    Repo.transaction(fn ->
      Repo.delete_all(from(c in RecoveryCode, where: c.user_id == ^user.id))
      Repo.delete_all(from(t in PasswordResetToken, where: t.user_id == ^user.id))
      Repo.delete_all(from(m in Botyaga.Access.Membership, where: m.user_id == ^user.id))
      Repo.delete!(user)
    end)
  end

  defp to_int("") do
    0
  end

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(value) when is_integer(value), do: value
end

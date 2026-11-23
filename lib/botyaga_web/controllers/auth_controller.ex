defmodule BotyagaWeb.AuthController do
  use BotyagaWeb, :controller

  alias Botyaga.{Accounts, Accounts.LoginLog, Accounts.Totp, RateLimit}
  alias BotyagaWeb.Respond

  def token(conn, params) do
    login = (params["sub"] || params["email"] || "") |> String.trim()

    if login == "" do
      Respond.error(conn, {422, "email или sub е задължителен"})
    else
      password = params["password"] || ""

      case RateLimit.login_locked(login) do
        nil ->
          do_token(conn, login, password)

        seconds ->
          LoginLog.record(conn, "locked", login, 0, "заключен след неуспешни опити")

          Respond.error(
            conn,
            {429, "твърде много неуспешни опити, опитайте след #{ceil(seconds / 60)} минути"}
          )
      end
    end
  end

  defp do_token(conn, login, password) do
    case Accounts.authenticate(login, password) do
      :error ->
        RateLimit.login_failure(login)
        LoginLog.record(conn, "login_failed", login, 0, "грешен потребител или парола")
        Respond.error(conn, {401, "грешен потребител или парола"})

      {:rehash, user} ->
        Accounts.rehash_password(user, password)
        login_success(conn, login, user)

      {:ok, user} ->
        login_success(conn, login, user)
    end
  end

  defp login_success(conn, login, user) do
    RateLimit.login_success(login)

    cond do
      user.is_active != 1 ->
        LoginLog.record(conn, "login_failed", login, user.id, "неактивен потребител")
        Respond.error(conn, {403, "потребителят е неактивен"})

      user.totp_enabled == 1 ->
        secret = Application.get_env(:botyaga, :jwt_secret)
        token = Accounts.JWT.issue(secret, user.username, user.session_version, 1)
        LoginLog.record(conn, "mfa_required", login, user.id)

        Respond.ok(conn, %{
          mfa: "totp",
          mfa_token: token,
          expires_in: Accounts.JWT.mfa_ttl(),
          message: "Въведи кода от приложението или резервен код"
        })

      true ->
        secret = Application.get_env(:botyaga, :jwt_secret)
        token = Accounts.JWT.issue(secret, user.username, user.session_version)
        LoginLog.record(conn, "login", login, user.id)

        Respond.ok(conn, %{
          access_token: token,
          token_type: "bearer",
          sub: user.username,
          expires_in: Accounts.JWT.ttl()
        })
    end
  end

  def mfa(conn, params) do
    token = (params["mfa_token"] || "") |> String.trim()

    if token == "" do
      Respond.error(conn, {422, "mfa_token е задължителен"})
    else
      code = (params["code"] || "") |> String.trim()

      if code == "" do
        Respond.error(conn, {422, "кодът е задължителен"})
      else
        verify_mfa(conn, token, code)
      end
    end
  end

  defp verify_mfa(conn, token, code) do
    secret = Application.get_env(:botyaga, :jwt_secret)

    case Accounts.JWT.decode(secret, token) do
      :error ->
        Respond.error(conn, {401, "изтекъл или невалиден 2FA токен"})

      {:ok, claims} ->
        if claims["mfa"] != 1 or claims["sub"] == "" do
          Respond.error(conn, {401, "изтекъл или невалиден 2FA токен"})
        else
          verify_mfa_user(conn, secret, claims["sub"], code)
        end
    end
  end

  defp verify_mfa_user(conn, _secret, sub, _code) when sub == "",
    do: Respond.error(conn, {401, "изтекъл или невалиден 2FA токен"})

  defp verify_mfa_user(conn, secret, sub, code) do
    user = Accounts.get_by_login(sub)

    if user == nil do
      Respond.error(conn, {401, "грешен код"})
    else
      now = System.system_time(:second)

      cond do
        user.mfa_lock_until > now ->
          Respond.error(conn, {429, "2FA е заключен за 15 минути след неуспешни опити"})

        true ->
          verify_mfa_code(conn, secret, user, code, now)
      end
    end
  end

  defp verify_mfa_code(conn, secret, user, code, now) do
    counter = Totp.totp_counter(user.totp_secret_b32, code, now)
    ok = not is_nil(counter) and Accounts.totp_consume_counter(user.id, counter)
    ok = if ok, do: true, else: Accounts.take_recovery(user.id, code)

    if ok do
      Accounts.mfa_reset(user)
      token = Accounts.JWT.issue(secret, user.username, user.session_version)
      LoginLog.record(conn, "login", user.username, user.id, "2FA")

      Respond.ok(conn, %{
        access_token: token,
        token_type: "bearer",
        sub: user.username,
        expires_in: Accounts.JWT.ttl()
      })
    else
      fails = Accounts.mfa_failure(user)

      if fails >= 5 do
        Accounts.mfa_lock(user, now + 900)
        LoginLog.record(conn, "locked", user.username, user.id, "2FA заключен")
        Respond.error(conn, {429, "изчерпани опити за 2FA — заключено за 15 минути"})
      else
        LoginLog.record(conn, "mfa_failed", user.username, user.id)
        Respond.error(conn, {401, "грешен код"})
      end
    end
  end

  @doc "Изход: обезсилва сесиите на потребителя и записва събитието."
  def logout(conn, _params) do
    secret = Application.get_env(:botyaga, :jwt_secret)
    token = bearer(conn)

    case Accounts.JWT.decode(secret, token) do
      {:ok, %{"sub" => sub}} when sub != "" ->
        case Accounts.get_by_login(sub) do
          nil ->
            Respond.ok(conn, %{ok: true})

          user ->
            Accounts.bump_version(user.id)
            LoginLog.record(conn, "logout", user.username, user.id)
            Respond.ok(conn, %{ok: true})
        end

      _ ->
        Respond.ok(conn, %{ok: true})
    end
  end

  defp bearer(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      [value | _] ->
        case String.trim(value) do
          "Bearer " <> token -> String.trim(token)
          "bearer " <> token -> String.trim(token)
          _ -> ""
        end

      [] ->
        ""
    end
  end
end

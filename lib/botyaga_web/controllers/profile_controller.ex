defmodule BotyagaWeb.ProfileController do
  use BotyagaWeb, :controller

  alias Botyaga.{Access, Accounts, Accounts.Totp, Companies}
  alias BotyagaWeb.{Render, Respond}

  def me(conn, _params) do
    user = conn.assigns.current_user
    permissions = permissions_for(user)

    Render.profile(user, permissions, Access.memberships_of(user.id))
    |> then(&Respond.ok(conn, &1))
  end

  def update_name(conn, params) do
    user = conn.assigns.current_user
    name = String.trim(params["name"] || "")

    if name == "" do
      Respond.error(conn, {422, "името е задължително"})
    else
      Accounts.set_name(user, name)
      Respond.ok(conn, %{message: "Името е записано", name: name})
    end
  end

  def change_password(conn, params) do
    user = conn.assigns.current_user
    current = params["current_password"] || ""
    new_password = params["new_password"] || ""

    cond do
      current == "" or new_password == "" ->
        Respond.error(conn, {422, "текущата и новата парола са задължителни"})

      not Accounts.password_ok?(user, current) ->
        Respond.error(conn, {401, "грешна парола"})

      String.length(new_password) < 8 ->
        Respond.error(conn, {422, "паролата трябва да е поне 8 символа"})

      true ->
        {:ok, version} = Accounts.set_password(user, new_password)
        token = Accounts.JWT.issue(secret(), user.username, version)
        Respond.ok(conn, %{message: "Паролата е сменена", access_token: token})
    end
  end

  def change_email(conn, params) do
    user = conn.assigns.current_user
    email = String.trim(params["email"] || "")
    current = params["current_password"] || ""

    cond do
      email == "" or current == "" ->
        Respond.error(conn, {422, "имейл и текуща парола са задължителни"})

      not valid_email?(email) ->
        Respond.error(conn, {422, "имейлът е невалиден"})

      not Accounts.password_ok?(user, current) ->
        Respond.error(conn, {401, "грешна парола"})

      Accounts.email_taken?(email, user.id) ->
        Respond.error(conn, {409, "имейлът вече се ползва"})

      true ->
        {:ok, version} = Accounts.set_email(user, email, current)
        token = Accounts.JWT.issue(secret(), user.username, version)

        Respond.ok(conn, %{
          message: "Имейлът е сменен",
          email: email,
          username: user.username,
          access_token: token
        })
    end
  end

  def totp_start(conn, params) do
    user = conn.assigns.current_user

    cond do
      not Accounts.password_ok?(user, params["current_password"] || "") ->
        Respond.error(conn, {401, "грешна парола"})

      user.totp_enabled == 1 ->
        Respond.error(conn, {409, "2FA вече е включена"})

      true ->
        secret = Totp.new_secret()
        account = if String.contains?(user.email || "", "@"), do: user.email, else: user.username
        uri = Totp.otpauth_uri(secret, account)
        svg = Totp.qr_svg(uri)
        codes = Totp.recovery_make()

        Accounts.wipe_recovery(user.id)
        Accounts.insert_recovery(user.id, Enum.map(codes, fn {_code, hash} -> hash end))
        Accounts.set_totp(user, 0, "", secret)

        Respond.ok(conn, %{
          secret: secret,
          uri: uri,
          qr_svg: svg,
          recovery_codes: Enum.map(codes, fn {code, _hash} -> code end),
          message: "Сканирай кода и запази резервните кодове. Показват се само сега."
        })
    end
  end

  def totp_confirm(conn, params) do
    user = conn.assigns.current_user
    code = String.trim(params["code"] || "")

    cond do
      not Accounts.password_ok?(user, params["current_password"] || "") ->
        Respond.error(conn, {401, "грешна парола"})

      code == "" ->
        Respond.error(conn, {422, "кодът е задължителен"})

      (user.totp_pending_b32 || "") == "" ->
        Respond.error(conn, {400, "няма започнато включване на 2FA"})

      true ->
        confirm_totp(conn, user, code)
    end
  end

  defp confirm_totp(conn, user, code) do
    now = System.system_time(:second)
    counter = Totp.totp_counter(user.totp_pending_b32, code, now)

    if not is_nil(counter) and Accounts.totp_consume_counter(user.id, counter) do
      Accounts.set_totp(user, 1, user.totp_pending_b32, "")
      Respond.ok(conn, %{ok: 1, totp_enabled: 1, message: "2FA е включена"})
    else
      Respond.error(conn, {401, "грешен код"})
    end
  end

  def totp_disable(conn, params) do
    user = conn.assigns.current_user
    password = params["password"] || ""
    code = String.trim(params["code"] || "")

    cond do
      password == "" or code == "" ->
        Respond.error(conn, {422, "парола и код са задължителни"})

      not Accounts.password_ok?(user, password) ->
        Respond.error(conn, {401, "грешна парола"})

      true ->
        disable_totp(conn, user, code)
    end
  end

  defp disable_totp(conn, user, code) do
    now = System.system_time(:second)
    counter = Totp.totp_counter(user.totp_secret_b32, code, now)
    ok = not is_nil(counter) and Accounts.totp_consume_counter(user.id, counter)
    ok = if ok, do: true, else: Accounts.take_recovery(user.id, code)

    if ok do
      Accounts.set_totp(user, 0, "", "")
      Accounts.wipe_recovery(user.id)
      Respond.ok(conn, %{ok: 1, totp_enabled: 0, message: "2FA е изключена"})
    else
      Respond.error(conn, {401, "грешен код"})
    end
  end

  defp permissions_for(user) do
    if user.is_super_admin == 1 do
      ["*"]
    else
      case Companies.resolve_active(user.username) do
        {:ok, company_id} -> Access.perms_for(user, company_id)
        {:error, _} -> []
      end
    end
  end

  defp valid_email?(email) do
    String.contains?(email, "@") and not String.contains?(email, " ") and byte_size(email) <= 200
  end

  defp secret, do: Application.get_env(:botyaga, :jwt_secret)
end

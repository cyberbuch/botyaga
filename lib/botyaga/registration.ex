defmodule Botyaga.Registration do
  @moduledoc "Публична регистрация и забравена парола."

  alias Botyaga.{Accounts, Access, Catalog, Companies, Emails, Repo, Settings}
  alias Botyaga.Accounts.PasswordResetToken

  def registration_enabled?, do: Settings.registration_enabled?()

  def register(params) do
    with :ok <- check_enabled(),
         {:ok, email} <- require_email(params["email"]),
         {:ok, name} <- require_name(params["name"]),
         {:ok, password} <- password_problem(params["password"], params["password_confirmation"]),
         {:ok, company_name} <-
           require_field(params["company_name"], "име на фирмата е задължително"),
         {:ok, eik} <- require_field(params["company_eik"], "ЕИК е задължителен") do
      do_register(params, email, name, password, company_name, eik)
    end
  end

  defp do_register(params, email, name, password, company_name, eik) do
    if Accounts.email_taken?(email) do
      Accounts.burn_password_check(password)
      Emails.registration_taken(email)
      {:ok, %{company_id: nil}}
    else
      with {:ok, company} <-
             Companies.new_for_register(%{
               "name" => company_name,
               "eik" => eik,
               "vat_number" => params["company_vat_number"] || "",
               "address" => params["company_address"] || "",
               "city" => params["company_city"] || "",
               "email" => email
             }) do
        insert_registered(company, email, name, password)
      end
    end
  end

  defp insert_registered(company, email, name, password) do
    Repo.transaction(fn ->
      company = Repo.insert!(company)
      Catalog.seed_chart(company.id)

      {:ok, user} = Accounts.create_user(email, name, password, "admin")
      {:ok, role_id} = Access.role_id_by_name(Access.role_admin())
      Settings.upsert(Companies.active_key(user.username), to_string(company.id))
      Access.grant(user.id, company.id, role_id)

      %{company_id: company.id, user_id: user.id}
    end)
  end

  def forgot_password(params) do
    email = String.trim(params["email"] || "")

    if email == "" do
      {:error, {422, "Email е задължителен"}}
    else
      if user = Accounts.get_by_email(email) do
        token = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

        Repo.insert!(%PasswordResetToken{
          user_id: user.id,
          token_hash: hash_token(token),
          expires_at: System.system_time(:second) + 3600
        })

        if Settings.mail_ready?() do
          link = "#{String.trim_trailing(Settings.app_url(), "/")}/reset-password?token=#{token}"
          Emails.reset_password(email, link)
        end
      end

      {:ok, %{message: "Ако съществува акаунт с този email, ще получите линк за възстановяване."}}
    end
  end

  def reset_password(params) do
    token = String.trim(params["token"] || "")

    if token == "" do
      {:error, {422, "Невалиден или липсващ токен"}}
    else
      with {:ok, password} <-
             password_problem(params["password"], params["password_confirmation"]),
           {:ok, user} <- token_user(token) do
        Accounts.set_password(user, password)
        {:ok, %{message: "Паролата е променена. Можете да влезете."}}
      end
    end
  end

  defp token_user(token) do
    hash = hash_token(token)
    now = System.system_time(:second)

    case Repo.get_by(PasswordResetToken, token_hash: hash) do
      %PasswordResetToken{used: 1} ->
        {:error, {422, "Невалиден или изтекъл токен. Заявете нов линк."}}

      %PasswordResetToken{expires_at: exp} when exp < now ->
        {:error, {422, "Невалиден или изтекъл токен. Заявете нов линк."}}

      %PasswordResetToken{user_id: user_id} ->
        case Accounts.get_by_id(user_id) do
          nil -> {:error, {422, "Невалиден или изтекъл токен. Заявете нов линк."}}
          user -> {:ok, user}
        end

      nil ->
        {:error, {422, "Невалиден или изтекъл токен. Заявете нов линк."}}
    end
  end

  defp check_enabled do
    if registration_enabled?(), do: :ok, else: {:error, {403, "Регистрацията е спряна."}}
  end

  defp require_email(nil), do: {:error, {422, "валиден email е задължителен"}}

  defp require_email(email) do
    email = String.trim(email)

    if String.contains?(email, "@"),
      do: {:ok, email},
      else: {:error, {422, "валиден email е задължителен"}}
  end

  defp require_name(nil), do: {:error, {422, "името е задължително"}}

  defp require_name(name) do
    if String.trim(name) == "",
      do: {:error, {422, "името е задължително"}},
      else: {:ok, String.trim(name)}
  end

  defp require_field(nil, message), do: {:error, {422, message}}

  defp require_field(value, message) do
    if String.trim(value) == "", do: {:error, {422, message}}, else: {:ok, String.trim(value)}
  end

  defp password_problem(nil, _confirm), do: {:error, {422, "паролата трябва да е поне 8 символа"}}

  defp password_problem(password, confirm) do
    confirm = if is_nil(confirm), do: password, else: confirm

    cond do
      is_nil(password) -> {:error, {422, "паролата трябва да е поне 8 символа"}}
      byte_size(password) < 8 -> {:error, {422, "паролата трябва да е поне 8 символа"}}
      password != confirm -> {:error, {422, "паролите не съвпадат"}}
      true -> {:ok, password}
    end
  end

  defp hash_token(token), do: Base.encode16(:crypto.hash(:sha256, token), case: :lower)
end

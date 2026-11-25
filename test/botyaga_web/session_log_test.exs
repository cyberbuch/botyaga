defmodule BotyagaWeb.SessionLogTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Access, Accounts, Companies}

  setup do
    {:ok, super} =
      Accounts.create_user("super@baga.example", "Супер", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(%{"name" => "Сесия ООД", "eik" => "207123456"}, super)

    Companies.set_active(super.username, company.id)

    {:ok, user} = Accounts.create_user("user@baga.example", "Потребител", "парола-123")
    {:ok, admin_role} = Access.role_id_by_name(Access.role_admin())
    Access.grant(user.id, company.id, admin_role)

    {:ok, super: super, user: user, company: company}
  end

  defp login(login, password) do
    post(build_conn(), "/v1/auth/token", %{"sub" => login, "password" => password})
  end

  test "вход и грешна парола се записват с IP", %{super: super} do
    conn = login("super@baga.example", "парола-123")
    assert json_response(conn, 200)["access_token"]

    conn = login("super@baga.example", "грешна")
    assert json_response(conn, 401)

    conn = auth_conn(build_conn(), super)
    body = json_response(get(conn, "/v1/admin/login-events"), 200)
    events = body["items"]

    assert Enum.any?(
             events,
             &(&1["event"] == "login" and &1["user_login"] == "super@baga.example")
           )

    assert Enum.any?(events, &(&1["event"] == "login_failed"))
    assert Enum.all?(events, &(&1["ip"] != ""))
  end

  test "изходът обезсилва сесията и се записва", %{super: super} do
    conn = login("user@baga.example", "парола-123")
    token = json_response(conn, 200)["access_token"]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    assert json_response(get(conn, "/v1/me"), 200)

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    assert json_response(post(conn, "/v1/auth/logout", %{}), 200)["ok"]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    assert json_response(get(conn, "/v1/me"), 401)

    conn = auth_conn(build_conn(), super)
    body = json_response(get(conn, "/v1/admin/login-events?event=logout"), 200)
    assert Enum.any?(body["items"], &(&1["user_login"] == "user@baga.example"))
  end

  test "админ матрицата носи потребители, членства, роли и фирми", %{
    super: super,
    user: user,
    company: company
  } do
    conn = auth_conn(build_conn(), super)
    body = json_response(get(conn, "/v1/admin/access"), 200)

    u = Enum.find(body["users"], &(&1["id"] == user.id))
    assert [m] = u["memberships"]
    assert m["company_id"] == company.id
    assert m["company_name"] == "Сесия ООД"
    assert m["role"] == Access.role_admin()
    assert Enum.any?(body["roles"], &(&1["name"] == Access.role_admin()))
    assert Enum.any?(body["companies"], &(&1["id"] == company.id))
  end

  test "прекратяване на сесиите вдига версията", %{super: super, user: user} do
    conn = login("user@baga.example", "парола-123")
    token = json_response(conn, 200)["access_token"]

    conn = auth_conn(build_conn(), super)
    assert json_response(post(conn, "/v1/admin/users/#{user.id}/revoke-sessions", %{}), 200)["ok"]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}")
    assert json_response(get(conn, "/v1/me"), 401)
  end

  test "обикновен потребител няма достъп до админ панела", %{user: user} do
    conn = auth_conn(build_conn(), user)
    assert json_response(get(conn, "/v1/admin/login-events"), 403)
    assert json_response(get(conn, "/v1/admin/access"), 403)
  end

  test "нов потребител иска фирма; суперадминът — не", %{super: super, company: company} do
    {:ok, role} = Access.role_id_by_name(Access.role_accountant())
    conn = auth_conn(build_conn(), super)

    conn =
      post(conn, "/v1/users", %{
        "email" => "x@baga.example",
        "name" => "X",
        "password" => "парола-123"
      })

    assert json_response(conn, 422)["detail"] =~ "фирма"

    conn = build_conn() |> auth_conn(super)

    conn =
      post(conn, "/v1/users", %{
        "email" => "x@baga.example",
        "name" => "X",
        "password" => "парола-123",
        "memberships" => [%{"company_id" => company.id, "role_id" => role}]
      })

    assert json_response(conn, 201)

    conn = build_conn() |> auth_conn(super)

    conn =
      post(conn, "/v1/users", %{
        "email" => "s@baga.example",
        "name" => "S",
        "password" => "парола-123",
        "is_super_admin" => 1
      })

    assert json_response(conn, 201)
  end

  test "редакция сменя членствата на потребителя", %{super: super, user: user, company: company} do
    {:ok, accountant} = Access.role_id_by_name(Access.role_accountant())
    conn = auth_conn(build_conn(), super)

    conn =
      patch(conn, "/v1/users/#{user.id}", %{
        "memberships" => [%{"company_id" => company.id, "role_id" => accountant}]
      })

    assert json_response(conn, 200)

    body = json_response(get(conn, "/v1/admin/access"), 200)
    u = Enum.find(body["users"], &(&1["id"] == user.id))
    assert [m] = u["memberships"]
    assert m["role"] == Access.role_accountant()
  end

  test "остарял токен не изхвърля живата сесия при изход", %{super: super, user: user} do
    old = json_response(login("user@baga.example", "парола-123"), 200)["access_token"]

    conn = auth_conn(build_conn(), super)
    assert json_response(post(conn, "/v1/admin/users/#{user.id}/revoke-sessions", %{}), 200)["ok"]

    fresh = json_response(login("user@baga.example", "парола-123"), 200)["access_token"]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{old}")
    assert json_response(post(conn, "/v1/auth/logout", %{}), 200)["ok"]

    conn = build_conn() |> put_req_header("authorization", "Bearer #{fresh}")
    assert json_response(get(conn, "/v1/me"), 200)
  end

  test "2FA токен след отнемане на сесиите не вади достъп", %{super: super, user: user} do
    secret = Botyaga.Accounts.Totp.new_secret()

    user =
      user
      |> Ecto.Changeset.change(totp_enabled: 1, totp_secret_b32: secret)
      |> Botyaga.Repo.update!()

    mfa_token =
      Botyaga.Accounts.JWT.issue(
        Application.get_env(:botyaga, :jwt_secret),
        user.username,
        user.session_version,
        1
      )

    conn = auth_conn(build_conn(), super)
    assert json_response(post(conn, "/v1/admin/users/#{user.id}/revoke-sessions", %{}), 200)["ok"]

    conn =
      post(build_conn(), "/v1/auth/mfa", %{"mfa_token" => mfa_token, "code" => totp_code(secret)})

    assert json_response(conn, 401)
  end

  test "чужда фирма: редакция и настройки искат право companies", %{
    super: super,
    user: user,
    company: company
  } do
    {:ok, other, _} = Companies.create(%{"name" => "Чужда ООД", "eik" => "207123457"}, super)
    {:ok, facturist} = Access.role_id_by_name("Фактурист")
    Access.grant(user.id, other.id, facturist)
    Companies.set_active(user.username, company.id)

    conn = auth_conn(build_conn(), user)
    assert json_response(patch(conn, "/v1/companies/#{other.id}", %{"name" => "Хак"}), 403)

    conn = auth_conn(build_conn(), user)
    assert json_response(get(conn, "/v1/companies/#{other.id}/settings"), 403)
  end

  test "невалиден флаг е 422, не грешка при записа", %{super: super, user: user} do
    conn = auth_conn(build_conn(), super)
    conn = patch(conn, "/v1/users/#{user.id}", %{"is_active" => "maybe"})
    assert json_response(conn, 422)
  end

  test "последното членство на потребител не се маха", %{
    super: super,
    user: user,
    company: company
  } do
    conn = auth_conn(build_conn(), super)
    conn = delete(conn, "/v1/companies/#{company.id}/users/#{user.id}")
    assert json_response(conn, 422)["detail"] =~ "фирма"
  end

  test "логът за влизания се ограничава до 20 дни" do
    old = DateTime.utc_now() |> DateTime.add(-21 * 86_400, :second) |> DateTime.truncate(:second)

    recent =
      DateTime.utc_now() |> DateTime.add(-2 * 86_400, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      Botyaga.Repo.insert(%Botyaga.Accounts.LoginEvent{
        user_login: "old@baga.example",
        event: "login",
        created_at: old
      })

    {:ok, _} =
      Botyaga.Repo.insert(%Botyaga.Accounts.LoginEvent{
        user_login: "recent@baga.example",
        event: "login",
        created_at: recent
      })

    Botyaga.Accounts.LoginLog.prune()

    logins =
      Botyaga.Repo.all(Botyaga.Accounts.LoginEvent)
      |> Enum.map(& &1.user_login)

    refute "old@baga.example" in logins
    assert "recent@baga.example" in logins
  end

  test "дълъг вход не събаря заявката" do
    conn = login(String.duplicate("a", 400), "парола-123")
    assert json_response(conn, 401)
  end

  # RFC 6238: SHA1, 6 цифри, 30 s — същият алгоритъм като Accounts.Totp.
  defp totp_code(secret_b32) do
    import Bitwise
    clean = secret_b32 |> String.replace("=", "")
    padded = clean <> String.duplicate("=", rem(8 - rem(byte_size(clean), 8), 8))
    {:ok, key} = Base.decode32(padded, case: :mixed)
    counter = div(System.system_time(:second), 30)
    mac = :crypto.mac(:hmac, :sha, key, <<counter::64>>)
    offset = :binary.last(mac) &&& 0x0F
    bin = mac |> binary_part(offset, 4) |> :binary.decode_unsigned() |> band(0x7FFF_FFFF)
    bin |> rem(1_000_000) |> to_string() |> String.pad_leading(6, "0")
  end
end

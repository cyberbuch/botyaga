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
end

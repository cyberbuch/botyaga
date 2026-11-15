defmodule BotyagaWeb.AuthFlowTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Access, Accounts, Companies}

  @register %{
    "email" => "nov@baga.example",
    "name" => "Нов Потребител",
    "password" => "парола-123",
    "password_confirmation" => "парола-123",
    "company_name" => "Нова Фирма ЕООД",
    "company_eik" => "123456789",
    "company_vat_number" => "BG123456789"
  }

  describe "регистрация и вход" do
    test "регистрация създава фирма, потребител и активна фирма" do
      conn = post(build_conn(), "/v1/auth/register", @register)
      assert json_response(conn, 201)["ok"] == 1

      user = Accounts.get_by_email!("nov@baga.example")
      assert user.role == "admin"

      company = Companies.get_company(Companies.active_company_id(user.username))
      assert company.name == "Нова Фирма ЕООД"
      assert company.eik == "123456789"
      assert Companies.can_access?(user, company.id)
      assert "companies" in Access.perms_for(user, company.id)
    end

    test "логин дава токен, /v1/me носи права и фирми" do
      register()

      conn =
        post(build_conn(), "/v1/auth/token", %{
          "sub" => "nov@baga.example",
          "password" => "парола-123"
        })

      assert json_response(conn, 200)["token_type"] == "bearer"

      conn =
        build_conn()
        |> auth_conn(Accounts.get_by_email!("nov@baga.example"))
        |> get("/v1/me")

      body = json_response(conn, 200)
      assert body["sub"] == "nov@baga.example"
      assert "companies" in body["permissions"]
      assert Enum.any?(body["companies"], &(&1["role"] == "Администратор на фирма"))
    end

    test "грешна парола и липсващ токен" do
      register()

      conn =
        post(build_conn(), "/v1/auth/token", %{
          "email" => "nov@baga.example",
          "password" => "грешна"
        })

      assert json_response(conn, 401)["detail"] == "грешен потребител или парола"

      conn = get(build_conn(), "/v1/me")
      assert json_response(conn, 401)["detail"] == "липсва токен"

      conn = build_conn() |> put_req_header("authorization", "Bearer лъжа") |> get("/v1/me")
      assert json_response(conn, 401)["detail"] == "невалиден токен"
    end

    test "непознат /v1 път е 404, а не отворен" do
      register()
      user = Accounts.get_by_email!("nov@baga.example")

      conn =
        build_conn()
        |> auth_conn(user)
        |> get("/v1/нещо")

      assert json_response(conn, 404)["detail"] == "непознат път"
    end

    test "публичните пътища не искат токен" do
      conn = get(build_conn(), "/v1/auth/registration-status")
      assert json_response(conn, 200)["registration_enabled"] == 1

      conn = get(build_conn(), "/health")
      assert json_response(conn, 200)["status"] == "ok"

      conn = get(build_conn(), "/ready")
      assert json_response(conn, 200)["database"] == "up"
    end
  end

  describe "валидиране на регистрацията" do
    test "задължителните полета са с точните съобщения" do
      conn = post(build_conn(), "/v1/auth/register", %{})
      assert json_response(conn, 422)["detail"] == "валиден email е задължителен"

      conn =
        post(build_conn(), "/v1/auth/register", %{"email" => "a@b.c", "password" => "парола-123"})

      assert json_response(conn, 422)["detail"] == "името е задължително"

      conn =
        post(build_conn(), "/v1/auth/register", %{
          "email" => "a@b.c",
          "name" => "И",
          "password" => "парола-123"
        })

      assert json_response(conn, 422)["detail"] == "име на фирмата е задължително"

      conn =
        post(build_conn(), "/v1/auth/register", %{
          "email" => "a@b.c",
          "name" => "И",
          "password" => "парола-123",
          "company_name" => "Ф"
        })

      assert json_response(conn, 422)["detail"] == "ЕИК е задължителен"
    end

    test "повторните пароли трябва да съвпадат" do
      conn =
        post(
          build_conn(),
          "/v1/auth/register",
          Map.merge(@register, %{"password_confirmation" => "друга"})
        )

      assert json_response(conn, 422)["detail"] == "паролите не съвпадат"
    end
  end

  defp register do
    post(build_conn(), "/v1/auth/register", @register)
  end
end

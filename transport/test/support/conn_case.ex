defmodule TransportWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TransportWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TransportWeb.Endpoint

      use TransportWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TransportWeb.ConnCase
    end
  end

  setup tags do
    Transport.DataCase.setup_sandbox(tags)
    start_supervised!(Transport.AccessStub)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Потребителят на теста става член на фирмата (за проби на чужда фирма)."
  def grant_company(sub, company_id) do
    Agent.update(Transport.AccessStub, &MapSet.put(&1, {sub, company_id}))
  end

  @doc "Връзка с валиден botyaga JWT (тест тайна) и фирма."
  def auth_conn(conn, sub \\ "test@baga.example", company_id \\ 1) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{issue_token(sub)}")
    |> Plug.Conn.put_req_header("x-company-id", to_string(company_id))
  end

  defp issue_token(sub) do
    {:ok, secret} = Transport.Auth.secret()
    now = System.system_time(:second)
    header = %{"alg" => "HS256", "typ" => "JWT"}

    claims = %{
      "sub" => sub,
      "iat" => now,
      "exp" => now + 3600,
      "iss" => "botyaga",
      "mfa" => 0,
      "ver" => 0
    }

    enc = fn data -> Base.url_encode64(data, padding: false) end
    signing = "#{enc.(Jason.encode!(header))}.#{enc.(Jason.encode!(claims))}"
    sig = :crypto.mac(:hmac, :sha256, secret, signing) |> enc.()
    "#{signing}.#{sig}"
  end
end

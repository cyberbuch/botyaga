defmodule BotyagaWeb.ConnCase do
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
  by setting `use BotyagaWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint BotyagaWeb.Endpoint

      use BotyagaWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import BotyagaWeb.ConnCase
    end
  end

  setup tags do
    Botyaga.DataCase.setup_sandbox(tags)
    Botyaga.RateLimit.reset()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Връзка с токен на потребителя — токенът е същият формат като на продукция."
  def auth_conn(conn, %Botyaga.Accounts.User{} = user) do
    token =
      Botyaga.Accounts.JWT.issue(
        Application.get_env(:botyaga, :jwt_secret),
        user.username,
        user.session_version
      )

    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end
end

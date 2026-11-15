defmodule Botyaga.Bootstrap do
  @moduledoc """
  Еднократни стъпки при старт: роли, тайна за JWT, backfill на членствата и
  суперадминистратор при празна база. Паролата не е фиксирана в кода.
  """

  use GenServer

  require Logger

  alias Botyaga.{Accounts, Access, Settings}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    run()
    {:ok, %{}}
  end

  def run do
    Access.ensure_roles()
    Access.backfill()

    secret = Settings.jwt_secret()
    Application.put_env(:botyaga, :jwt_secret, secret)

    password = System.get_env("BOTYAGA_SUPERADMIN_PASSWORD")

    password =
      case password do
        nil -> generate_password()
        "" -> generate_password()
        password -> password
      end

    case Accounts.provision_superadmin(password) do
      {:ok, %Accounts.User{}} ->
        Logger.warning(
          "Създаден е superadmin с еднократна парола: #{password} — смени я веднага от Профил. " <>
            "За парола по твой избор задай BOTYAGA_SUPERADMIN_PASSWORD преди първия старт."
        )

      _ ->
        :ok
    end

    :ok
  end

  defp generate_password, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end

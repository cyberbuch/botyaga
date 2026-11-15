defmodule Botyaga.Repo do
  use Ecto.Repo,
    otp_app: :botyaga,
    adapter: Ecto.Adapters.Postgres
end

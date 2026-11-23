defmodule Transport.Release do
  @moduledoc "Миграции при деплой: bin/transport eval 'Transport.Release.migrate'"

  @app :transport

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end

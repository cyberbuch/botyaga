defmodule Botyaga.Repo.Migrations.CreateLoginEvents do
  use Ecto.Migration

  def change do
    create table(:login_events) do
      add :user_id, :bigint, default: 0, null: false
      add :user_login, :string, default: "", null: false
      add :event, :string, null: false
      add :ip, :string, default: "", null: false
      add :user_agent, :string, default: "", null: false
      add :detail, :string, default: "", null: false
      add :created_at, :utc_datetime
    end

    create index(:login_events, [:user_id])
    create index(:login_events, [:created_at])
  end
end

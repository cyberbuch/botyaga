defmodule Botyaga.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  def change do
    create table(:attachments) do
      add :company_id, :bigint, null: false
      add :doc_type, :string, null: false
      add :doc_id, :bigint, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false, default: "application/octet-stream"
      add :size, :bigint, null: false, default: 0
      add :data, :binary, null: false
      add :created_at, :utc_datetime
    end

    create index(:attachments, [:company_id, :doc_type, :doc_id])
  end
end

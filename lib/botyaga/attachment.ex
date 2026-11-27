defmodule Botyaga.Attachment do
  @moduledoc "Прикачен файл към документ (производство, комплектоване и др.)."
  use Ecto.Schema

  schema "attachments" do
    field :company_id, :integer
    field :doc_type, :string
    field :doc_id, :integer
    field :filename, :string
    field :content_type, :string, default: "application/octet-stream"
    field :size, :integer, default: 0
    field :data, :binary
    field :created_at, :utc_datetime
  end
end

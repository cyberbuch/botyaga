defmodule Botyaga.Oss.Declaration do
  @moduledoc "Тримесечна OSS справка-декларация по чл.159 ЗДДС (Приложение 32)."
  use Ecto.Schema

  schema "oss_declarations" do
    field :company_id, :integer
    field :year, :integer
    field :quarter, :integer
    field :status, :string, default: "draft"
    field :submitted_at, :string, default: ""
    field :submission_no, :string, default: ""
    field :frozen, :string
    timestamps(type: :utc_datetime)
  end
end

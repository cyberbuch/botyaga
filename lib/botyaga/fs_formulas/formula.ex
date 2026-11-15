defmodule Botyaga.FsFormulas.Formula do
  use Ecto.Schema

  schema "fs_line_formulas" do
    field :company_id, :id
    field :statement, :string
    field :line_code, :string
    field :formula, :string

    timestamps(type: :utc_datetime)
  end
end

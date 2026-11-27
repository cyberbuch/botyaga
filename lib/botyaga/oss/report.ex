defmodule Botyaga.Oss.Report do
  @moduledoc "OSS отчет за доставки по чл.119, ал.5 ЗДДС (режим в Съюза)."
  use Ecto.Schema

  schema "oss_reports" do
    field :company_id, :integer
    field :number, :string, default: ""
    field :doc_date, :string, default: ""
    field :month, :string, default: ""
    field :status, :string, default: "draft"
    field :correction_of_id, :integer, default: 0
    field :correction_quarter, :string, default: ""
    field :notes, :string, default: ""
    field :journal_entry_id, :integer, default: 0
    timestamps(type: :utc_datetime)
  end
end

defmodule Botyaga.Audit.Log do
  use Ecto.Schema

  schema "audit_logs" do
    field :company_id, :id
    field :user_id, :integer
    field :user_login, :string
    field :user_name, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :entity_number, :string
    field :action, :string
    field :summary, :string
    field :old_amount, :string
    field :new_amount, :string
    field :old_data, :string
    field :new_data, :string
    field :created_at, :utc_datetime
  end
end

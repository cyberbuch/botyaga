defmodule Botyaga.Assets.Event do
  use Ecto.Schema

  schema "fixed_asset_events" do
    field :asset_id, :integer
    field :event_type, :string
    field :event_date, :string
    field :amount, :string
    field :prev_value, :string
    field :location, :string
    field :reason, :string

    timestamps(type: :utc_datetime)
  end
end

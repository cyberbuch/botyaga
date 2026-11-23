defmodule Transport.Vehicles do
  @moduledoc "Автомобили: гориво, нормативен разход, зимна надбавка, резервоар."

  import Ecto.Query
  import Transport.Params
  alias Transport.Repo
  alias Transport.Vehicles.Vehicle

  def list(company_id),
    do: Repo.all(from(v in Vehicle, where: v.company_id == ^company_id, order_by: [asc: v.id]))

  def get(company_id, id), do: Repo.get_by(Vehicle, id: id, company_id: company_id)

  def create(company_id, params) do
    with {:ok, name} <- required(params, "name") do
      %Vehicle{}
      |> Ecto.Changeset.change(attrs(company_id, params, name))
      |> Repo.insert()
      |> ok()
    end
  end

  def update(%Vehicle{} = v, params) do
    with {:ok, name} <- required(%{"name" => Map.get(params, "name", v.name)}, "name") do
      v |> Ecto.Changeset.change(attrs(v.company_id, params, name)) |> Repo.update() |> ok()
    end
  end

  def delete(%Vehicle{} = v), do: Repo.delete(v)

  defp attrs(company_id, params, name) do
    %{
      company_id: company_id,
      name: name,
      plate: str(params, "plate"),
      fuel: str(params, "fuel") |> default("Дизел"),
      norm: str(params, "norm") |> default("0"),
      winter_surcharge: int(params, "winter_surcharge"),
      tank_volume: str(params, "tank_volume"),
      active: flag(params, "active", 1),
      note: str(params, "note")
    }
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  def json(%Vehicle{} = v) do
    %{
      id: v.id,
      name: v.name,
      plate: v.plate,
      fuel: v.fuel,
      norm: v.norm,
      winter_surcharge: v.winter_surcharge,
      tank_volume: v.tank_volume,
      active: v.active,
      note: v.note
    }
  end
end

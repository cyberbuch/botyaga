defmodule Transport.Vehicles do
  @moduledoc "Автомобили: гориво, нормативен разход, зимна надбавка, резервоар."

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo}
  alias Transport.Vehicles.Vehicle

  @fields ~w(name plate fuel norm tank_volume note)a

  def list(company_id),
    do: Repo.all(from(v in Vehicle, where: v.company_id == ^company_id, order_by: [asc: v.id]))

  def get(company_id, id), do: Repo.get_by(Vehicle, id: id, company_id: company_id)

  # Изтриването оставя пътните листи без автомобил — затова се отказва.
  def delete(%Vehicle{} = v) do
    if referenced?(v.id),
      do: {:error, {422, "автомобилът има пътни листове и не може да се изтрие"}},
      else: Repo.delete(v) |> ok()
  end

  def create(company_id, params), do: write(%Vehicle{company_id: company_id}, params)

  def update(%Vehicle{} = v, params) do
    current =
      %{"winter_surcharge" => v.winter_surcharge, "active" => v.active}
      |> Map.merge(current(v, @fields))

    write(v, merge(current, params))
  end

  defp write(%Vehicle{} = v, params) do
    with {:ok, name} <- required(params, "name"),
         :ok <- numeric(params, ["norm", "tank_volume"]) do
      %{
        name: name,
        plate: str(params, "plate"),
        fuel: default(str(params, "fuel"), "Дизел"),
        norm: Dec.canon(default(str(params, "norm"), "0")),
        winter_surcharge: int(params, "winter_surcharge"),
        tank_volume: Dec.canon(str(params, "tank_volume")),
        active: flag(params, "active", 1),
        note: str(params, "note")
      }
      |> then(&Ecto.Changeset.change(v, &1))
      |> save()
    end
  end

  defp referenced?(id),
    do: Repo.exists?(from(w in Transport.Waybills.Waybill, where: w.vehicle_id == ^id))

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

defmodule Transport.Drivers do
  @moduledoc "Шофьори."

  import Ecto.Query
  import Transport.Params
  alias Transport.Repo
  alias Transport.Drivers.Driver

  def list(company_id),
    do: Repo.all(from(d in Driver, where: d.company_id == ^company_id, order_by: [asc: d.id]))

  def get(company_id, id), do: Repo.get_by(Driver, id: id, company_id: company_id)

  def create(company_id, params) do
    with {:ok, name} <- required(params, "name") do
      %Driver{} |> Ecto.Changeset.change(attrs(company_id, params, name)) |> Repo.insert() |> ok()
    end
  end

  def update(%Driver{} = d, params) do
    with {:ok, name} <- required(%{"name" => Map.get(params, "name", d.name)}, "name") do
      d |> Ecto.Changeset.change(attrs(d.company_id, params, name)) |> Repo.update() |> ok()
    end
  end

  def delete(%Driver{} = d), do: Repo.delete(d)

  defp attrs(company_id, params, name) do
    %{
      company_id: company_id,
      name: name,
      egn: str(params, "egn"),
      license_number: str(params, "license_number"),
      phone: str(params, "phone"),
      active: flag(params, "active", 1),
      note: str(params, "note")
    }
  end

  def json(%Driver{} = d) do
    %{
      id: d.id,
      name: d.name,
      egn: d.egn,
      license_number: d.license_number,
      phone: d.phone,
      active: d.active,
      note: d.note
    }
  end
end

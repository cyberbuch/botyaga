defmodule Transport.Drivers do
  @moduledoc "Шофьори."

  import Ecto.Query
  import Transport.Params
  alias Transport.Repo
  alias Transport.Drivers.Driver

  @fields ~w(name egn license_number phone note)a

  def list(company_id),
    do: Repo.all(from(d in Driver, where: d.company_id == ^company_id, order_by: [asc: d.id]))

  def get(company_id, id), do: Repo.get_by(Driver, id: id, company_id: company_id)

  def create(company_id, params), do: write(%Driver{company_id: company_id}, params)

  def update(%Driver{} = d, params) do
    current = d |> current(@fields) |> Map.put("active", d.active)
    write(d, merge(current, params))
  end

  # Изтриването оставя пътните листи без шофьор — затова се отказва.
  def delete(%Driver{} = d) do
    if Repo.exists?(from(w in Transport.Waybills.Waybill, where: w.driver_id == ^d.id)),
      do: {:error, {422, "шофьорът има пътни листове и не може да се изтрие"}},
      else: Repo.delete(d) |> ok()
  end

  defp write(%Driver{} = d, params) do
    with {:ok, name} <- required(params, "name") do
      %{
        name: name,
        egn: str(params, "egn"),
        license_number: str(params, "license_number"),
        phone: str(params, "phone"),
        active: flag(params, "active", 1),
        note: str(params, "note")
      }
      |> then(&Ecto.Changeset.change(d, &1))
      |> save()
    end
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

defmodule Transport.Destinations do
  @moduledoc """
  Дестинации и ставки за командировки. България (вътрешни) и чужбина (държава + град).
  Ставките са по Наредбата за командировките (2026, EUR).
  """

  import Ecto.Query
  import Transport.Params
  alias Transport.{Dec, Repo}
  alias Transport.Destinations.Destination

  @fields ~w(country city kind per_diem per_diem_no_overnight lodging_limit)a

  def list(kind \\ nil) do
    query = from(d in Destination, order_by: [asc: d.kind, asc: d.country, asc: d.city])
    query = if kind in ["domestic", "abroad"], do: where(query, [d], d.kind == ^kind), else: query
    Repo.all(query)
  end

  def get(id), do: Repo.get(Destination, id)

  def create(params), do: write(%Destination{}, params)

  def update(%Destination{} = d, params) do
    current = d |> current(@fields) |> Map.put("active", d.active)
    write(d, merge(current, params))
  end

  # Изтриването оставя командировките без дестинация — затова се отказва.
  def delete(%Destination{} = d) do
    if Repo.exists?(from(t in Transport.Trips.Trip, where: t.destination_id == ^d.id)),
      do: {:error, {422, "дестинацията има командировки и не може да се изтрие"}},
      else: Repo.delete(d) |> ok()
  end

  defp write(%Destination{} = d, params) do
    with {:ok, country} <- required(params, "country"),
         :ok <- numeric(params, ["per_diem", "per_diem_no_overnight", "lodging_limit"]) do
      kind = str(params, "kind")
      kind = if kind in ["domestic", "abroad"], do: kind, else: "abroad"

      %{
        country: country,
        city: str(params, "city"),
        kind: kind,
        per_diem: Dec.canon(default(str(params, "per_diem"), "0")),
        per_diem_no_overnight: Dec.canon(default(str(params, "per_diem_no_overnight"), "0")),
        lodging_limit: Dec.canon(default(str(params, "lodging_limit"), "0")),
        active: flag(params, "active", 1)
      }
      |> then(&Ecto.Changeset.change(d, &1))
      |> save()
    end
  end

  defp default("", value), do: value
  defp default(value, _), do: value

  def json(%Destination{} = d) do
    %{
      id: d.id,
      country: d.country,
      city: d.city,
      kind: d.kind,
      per_diem: d.per_diem,
      per_diem_no_overnight: d.per_diem_no_overnight,
      lodging_limit: d.lodging_limit,
      active: d.active
    }
  end

  @doc "Начално зареждане на ставките по наредбата (ако таблицата е празна)."
  def seed do
    if Repo.aggregate(Destination, :count, :id) == 0 do
      Enum.each(rows(), fn row ->
        %Destination{} |> Ecto.Changeset.change(row) |> Repo.insert!()
      end)
    end
  end

  defp rows do
    domestic = [
      %{
        country: "България",
        city: "",
        kind: "domestic",
        per_diem: "22",
        per_diem_no_overnight: "11",
        lodging_limit: "0"
      }
    ]

    abroad =
      [
        {"Германия", "56", "207"},
        {"Австрия", "57", "200"},
        {"Франция", "58", "210"},
        {"Италия", "56", "200"},
        {"Испания", "54", "190"},
        {"Гърция", "43", "150"},
        {"Турция", "39", "140"},
        {"Сърбия", "39", "130"},
        {"Северна Македония", "39", "120"},
        {"Албания", "39", "120"},
        {"Румъния", "40", "130"},
        {"Великобритания", "60", "220"},
        {"Швейцария", "87", "280"},
        {"САЩ", "58", "220"},
        {"Канада", "58", "210"},
        {"Нидерландия", "57", "200"},
        {"Белгия", "56", "200"},
        {"Полша", "44", "150"},
        {"Чехия", "45", "160"},
        {"Унгария", "43", "150"}
      ]
      |> Enum.map(fn {country, diem, lodging} ->
        %{
          country: country,
          city: "",
          kind: "abroad",
          per_diem: diem,
          per_diem_no_overnight: diem,
          lodging_limit: lodging
        }
      end)

    domestic ++ abroad
  end
end

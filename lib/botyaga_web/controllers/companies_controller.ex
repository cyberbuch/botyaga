defmodule BotyagaWeb.CompaniesController do
  use BotyagaWeb, :controller

  alias Botyaga.Companies
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    conn.assigns.current_user
    |> Companies.index_for()
    |> Enum.map(&Render.company/1)
    |> Render.page(params)
    |> then(&Respond.ok(conn, &1))
  end

  def create(conn, params) do
    case Companies.create(params, conn.assigns.current_user) do
      {:ok, company, seeded} ->
        company
        |> Render.company()
        |> Map.put(:saft_accounts_seeded, seeded)
        |> then(&Respond.ok(conn, &1, 201))

      {:error, {status, detail}} ->
        Respond.error(conn, {status, detail})

      {:error, :forbidden} ->
        Respond.error(conn, {403, "създаването на фирма е за супер администратор"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Companies.fetch_accessible(conn.assigns.current_user, id) do
      {:ok, company} -> company |> Render.company() |> then(&Respond.ok(conn, &1))
      {:error, :not_found} -> Respond.error(conn, {404, "фирмата не е намерена"})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Companies.update(id, params, conn.assigns.current_user) do
      {:ok, company} -> company |> Render.company() |> then(&Respond.ok(conn, &1))
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
      {:error, :not_found} -> Respond.error(conn, {404, "фирмата не е намерена"})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Companies.delete(id, conn.assigns.current_user) do
      {:ok, nil} ->
        Respond.no_content(conn)

      {:error, :not_found} ->
        Respond.error(conn, {404, "фирмата не е намерена"})

      {:error, :forbidden} ->
        Respond.error(conn, {403, "изтриването на фирма е за супер администратор"})
    end
  end

  def active_get(conn, _params) do
    case Companies.active_company(conn.assigns.current_user.username) do
      nil -> Respond.ok(conn, %{})
      company -> company |> Render.company() |> then(&Respond.ok(conn, &1))
    end
  end

  def active_set(conn, params) do
    company_id = params["company_id"]

    if is_nil(company_id) do
      Respond.error(conn, {422, "company_id е задължителен"})
    else
      case Companies.set_active(conn.assigns.current_user.username, to_integer(company_id)) do
        {:ok, company} -> company |> Render.company() |> then(&Respond.ok(conn, &1))
        {:error, :not_found} -> Respond.error(conn, {404, "фирмата не е намерена"})
      end
    end
  end

  def dashboard(conn, _params) do
    Companies.dashboard(conn.assigns.current_user.username) |> then(&Respond.ok(conn, &1))
  end

  def settings(conn, %{"id" => id}) do
    case Companies.fetch_editable(conn.assigns.current_user, id) do
      {:error, :not_found} ->
        Respond.error(conn, {404, "фирмата не е намерена"})

      {:error, {status, detail}} ->
        Respond.error(conn, {status, detail})

      {:ok, _company} ->
        data = Companies.company_settings(to_integer(id))

        Respond.ok(conn, %{
          company: Render.company(data.company),
          locations: Enum.map(data.locations, &Render.location/1),
          beneficial_owners: Enum.map(data.beneficial_owners, &Render.owner/1),
          ultimate_parents: Enum.map(data.ultimate_parents, &Render.parent/1),
          document_series: Enum.map(data.document_series, &Render.series/1)
        })
    end
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end
end

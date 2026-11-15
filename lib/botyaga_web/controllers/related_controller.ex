defmodule BotyagaWeb.RelatedController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Companies.Related}
  alias BotyagaWeb.{Render, Respond}

  ## Обекти

  def create_location(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- active_company(conn, company_id) do
      create(conn, fn -> Related.create_location(company_id, params) end, &Render.location/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update_location(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active_company(conn, nil) do
      update(conn, fn -> Related.update_location(company_id, id, params) end, &Render.location/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_location(conn, %{"id" => id}) do
    with {:ok, company_id} <- active_company(conn, nil) do
      delete(conn, fn -> Related.delete_location(company_id, id) end)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Собственици

  def create_owner(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- active_company(conn, company_id) do
      create(conn, fn -> Related.create_owner(company_id, params) end, &Render.owner/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update_owner(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active_company(conn, nil) do
      update(conn, fn -> Related.update_owner(company_id, id, params) end, &Render.owner/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_owner(conn, %{"id" => id}) do
    with {:ok, company_id} <- active_company(conn, nil) do
      delete(conn, fn -> Related.delete_owner(company_id, id) end)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Крайни майки

  def create_parent(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- active_company(conn, company_id) do
      create(conn, fn -> Related.create_parent(company_id, params) end, &Render.parent/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update_parent(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active_company(conn, nil) do
      update(conn, fn -> Related.update_parent(company_id, id, params) end, &Render.parent/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_parent(conn, %{"id" => id}) do
    with {:ok, company_id} <- active_company(conn, nil) do
      delete(conn, fn -> Related.delete_parent(company_id, id) end)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Серии

  def create_series(conn, %{"id" => company_id} = params) do
    with {:ok, company_id} <- active_company(conn, company_id) do
      create(conn, fn -> Related.create_series(company_id, params) end, &Render.series/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update_series(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active_company(conn, nil) do
      update(conn, fn -> Related.update_series(company_id, id, params) end, &Render.series/1)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_series(conn, %{"id" => id}) do
    with {:ok, company_id} <- active_company(conn, nil) do
      delete(conn, fn -> Related.delete_series(company_id, id) end)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Общи

  defp active_company(conn, nil) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} -> {:ok, company_id}
      {:error, _} -> {:error, {404, "фирмата не е намерена"}}
    end
  end

  defp active_company(conn, company_id) do
    with {:ok, active} <- active_company(conn, nil) do
      if active == to_integer(company_id),
        do: {:ok, active},
        else: {:error, {404, "фирмата не е намерена"}}
    end
  end

  defp create(conn, fun, render) do
    case fun.() do
      {:ok, record} -> conn |> Respond.ok(render.(record), 201)
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
    end
  end

  defp update(conn, fun, render) do
    case fun.() do
      {:ok, record} -> conn |> Respond.ok(render.(record))
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
    end
  end

  defp delete(conn, fun) do
    case fun.() do
      {:ok, nil} -> Respond.no_content(conn)
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
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

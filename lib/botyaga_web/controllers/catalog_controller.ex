defmodule BotyagaWeb.CatalogController do
  use BotyagaWeb, :controller

  alias Botyaga.{Catalog, Companies}
  alias Botyaga.Catalog.{Accounts, Cn8, Counterparts, Products}
  alias BotyagaWeb.{Render, Respond}

  ## Сметкоплан

  def accounts(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id
      |> Accounts.list()
      |> Enum.map(&Render.account/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def account_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, account} <- Accounts.create(company_id, params) do
      conn |> Respond.ok(Render.account(account), 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def account_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, account} <- Accounts.get(company_id, id) do
      Respond.ok(conn, Render.account(account))
    else
      error -> Respond.error(conn, error)
    end
  end

  def account_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, account} <- Accounts.update(company_id, id, params) do
      Respond.ok(conn, Render.account(account))
    else
      error -> Respond.error(conn, error)
    end
  end

  def account_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Accounts.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def seed_saft(conn, _params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Accounts.seed(company_id))
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Контрагенти

  def counterparts(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id
      |> Counterparts.list()
      |> Enum.map(&Render.counterpart/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def counterpart_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, counterpart} <- Counterparts.create(company_id, params) do
      conn |> Respond.ok(Render.counterpart(counterpart), 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def counterpart_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, counterpart} <- Counterparts.get(company_id, id) do
      Respond.ok(conn, Render.counterpart(counterpart))
    else
      error -> Respond.error(conn, error)
    end
  end

  def counterpart_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, counterpart} <- Counterparts.update(company_id, id, params) do
      Respond.ok(conn, Render.counterpart(counterpart))
    else
      error -> Respond.error(conn, error)
    end
  end

  def counterpart_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Counterparts.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Стоки

  def products(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id
      |> Products.list()
      |> Enum.map(&Render.product/1)
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def product_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, product} <- Products.create(company_id, params) do
      conn |> Respond.ok(Render.product(product), 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def product_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, product} <- Products.get(company_id, id) do
      Respond.ok(conn, Render.product(product))
    else
      error -> Respond.error(conn, error)
    end
  end

  def product_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, product} <- Products.update(company_id, id, params) do
      Respond.ok(conn, Render.product(product))
    else
      error -> Respond.error(conn, error)
    end
  end

  def product_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Products.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def cn8_suggest(conn, params) do
    case Cn8.suggest(params) do
      {:ok, suggestion} -> Respond.ok(conn, suggestion)
      {:error, {status, detail}} -> Respond.error(conn, {status, detail})
    end
  end

  ## Номенклатури

  def nomenclatures(conn, params) do
    kind = params["kind"] || ""

    case Catalog.nomenclatures(kind, params["search"] || "") do
      {:ok, :cn8} ->
        limit = Render.int_param(params, "limit", 100) |> max(1) |> min(500)
        offset = Render.int_param(params, "offset", 0)
        {count, items} = Cn8.search_noms(params["search"] || "", limit, offset)
        Respond.ok(conn, %{kind: kind, items: items, count: count, limit: limit, offset: offset})

      {:ok, data} ->
        Respond.ok(conn, data)

      {:error, {status, detail}} ->
        Respond.error(conn, {status, detail})
    end
  end

  def units(conn, params) do
    Respond.ok(conn, Catalog.units(params["search"] || ""))
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} -> {:ok, company_id}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

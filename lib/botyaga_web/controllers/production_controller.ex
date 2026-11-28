defmodule BotyagaWeb.ProductionController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Params}
  alias Botyaga.Production.{Cards, Orders, Recipes}
  alias Botyaga.Printing.Protocol
  alias BotyagaWeb.{Render, Respond}

  ## Рецепти

  def recipes(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Recipes.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.show(company_id, id) do
      Respond.ok(conn, recipe)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.create(company_id, params) do
      Respond.ok(conn, recipe, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, recipe} <- Recipes.update(company_id, id, params) do
      Respond.ok(conn, recipe)
    else
      error -> Respond.error(conn, error)
    end
  end

  def recipe_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Recipes.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Поръчки

  def orders(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Orders.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.show(company_id, id) do
      Respond.ok(conn, order)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, order, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Orders.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, order} <- Orders.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, order)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Месечни производствени карти (фактическо производство)

  def cards(conn, _params) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{items: Cards.list(cid)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def card(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, c} <- Cards.get(cid, id) do
      Respond.ok(conn, c)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_create(conn, params) do
    with {:ok, cid} <- active(conn),
         {:ok, c} <- Cards.create(cid, params) do
      Respond.ok(conn, c, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_update(conn, %{"id" => id} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, c} <- Cards.update(cid, id, params) do
      Respond.ok(conn, c)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_delete(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn),
         {:ok, _} <- Cards.delete(cid, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_preview(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, p} <- Cards.preview(cid, id) do
      Respond.ok(conn, p)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_confirm(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, c} <- Cards.confirm(cid, id) do
      Respond.ok(conn, c)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_unpost(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, c} <- Cards.unpost(cid, id) do
      Respond.ok(conn, c)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_link(conn, %{"id" => id} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, o} <- Orders.link(cid, id, Params.integer(params, "card_id") || 0) do
      Respond.ok(conn, o)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_unlink(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, o} <- Orders.unlink(cid, id) do
      Respond.ok(conn, o)
    else
      error -> Respond.error(conn, error)
    end
  end

  def card_linkable(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, c} <- Cards.get(cid, id) do
      Respond.ok(conn, %{items: Orders.linkable(cid, c.month)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_copy(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn),
         {:ok, o} <- Orders.copy(cid, conn.assigns.current_user.username, id) do
      Respond.ok(conn, o, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def order_pdf(conn, %{"id" => id}) do
    pdf(conn, "production_order", id)
  end

  def card_pdf(conn, %{"id" => id}) do
    pdf(conn, "production_card", id)
  end

  defp pdf(conn, kind, id) do
    with {:ok, cid} <- active(conn),
         {:ok, r} <- Protocol.render(cid, kind, id) do
      conn
      |> put_resp_header("content-type", r.mime)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{r.filename}"))
      |> send_resp(200, r.bytes)
    else
      error -> Respond.error(conn, error)
    end
  end

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, company_id} when company_id > 0 -> {:ok, company_id}
      {:ok, _} -> {:error, {422, "няма избрана активна фирма"}}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

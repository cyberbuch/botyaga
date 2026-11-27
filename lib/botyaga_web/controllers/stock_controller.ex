defmodule BotyagaWeb.StockController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Printing, Stock}
  alias Botyaga.Stock.{Kits, InternalDocs, MaterialIssues, ProductionReceipts, Rules, Writeoff}
  alias Botyaga.Printing.Protocol
  alias BotyagaWeb.{Render, Respond}

  def rules(conn, _params) do
    with {:ok, company_id} <- active(conn) do
      items = Rules.index(company_id)
      Respond.ok(conn, %{items: items, count: length(items)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def create_rule(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, rule} <- Rules.create(company_id, params) do
      Respond.ok(conn, rule, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_rule(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Rules.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def rebuild(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Writeoff.rebuild(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def writeoff(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Writeoff.post(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def report(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Stock.report(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def at_location(conn, params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, Stock.at_location(company_id, params["location_id"]))
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Ръчно изписване на материали

  def material_issues(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> MaterialIssues.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- MaterialIssues.show(company_id, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           MaterialIssues.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, doc, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           MaterialIssues.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- MaterialIssues.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- MaterialIssues.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def material_issue_unpost(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- MaterialIssues.unpost(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Ръчен приход на продукция

  def production_receipt_preview(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- ProductionReceipts.preview(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipts(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id
      |> ProductionReceipts.index()
      |> Render.page(params)
      |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- ProductionReceipts.show(company_id, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           ProductionReceipts.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, doc, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           ProductionReceipts.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <-
           ProductionReceipts.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           ProductionReceipts.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def production_receipt_unpost(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           ProductionReceipts.unpost(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Вътрешни протоколи

  def internal_doc_next_number(conn, _params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- InternalDocs.next_number(company_id) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_docs(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> InternalDocs.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_show(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- InternalDocs.show(company_id, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_print(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, result} <- Printing.Idoc.build(company_id, id, Map.get(params, "format", "")) do
      Respond.attachment(conn, result.bytes, Printing.mime(result.format), result.filename)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- InternalDocs.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, doc, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <-
           InternalDocs.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- InternalDocs.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def internal_doc_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, doc} <- InternalDocs.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, doc)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Комплектоване

  def kits(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Kits.index() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn), {:ok, k} <- Kits.show(company_id, id) do
      Respond.ok(conn, k)
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit_create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, k} <- Kits.create(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, k, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit_update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, k} <- Kits.update(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, k)
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit_delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, _} <- Kits.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit_confirm(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, k} <- Kits.confirm(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, k)
    else
      error -> Respond.error(conn, error)
    end
  end

  def kit_unpost(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, k} <- Kits.unpost(company_id, conn.assigns.current_user.username, id) do
      Respond.ok(conn, k)
    else
      error -> Respond.error(conn, error)
    end
  end

  def receipt_pdf(conn, %{"id" => id}), do: pdf(conn, "production_receipt", id)
  def kit_pdf(conn, %{"id" => id}), do: pdf(conn, "kit", id)

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
      {:ok, company_id} -> {:ok, company_id}
      {:error, :no_access} -> {:error, {403, "нямате достъп до фирма"}}
      {:error, _} -> {:error, {401, "потребителят не съществува"}}
    end
  end
end

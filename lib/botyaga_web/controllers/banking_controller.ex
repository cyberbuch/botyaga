defmodule BotyagaWeb.BankingController do
  use BotyagaWeb, :controller

  alias Botyaga.{Banking, Companies}
  alias Botyaga.Banking.{Formats, Rules, Tx}
  alias BotyagaWeb.{Render, Respond}

  def formats(conn, _params) do
    Respond.ok(conn, %{items: Formats.list()})
  end

  def index(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Banking.list() |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, account} <- Banking.create(company_id, params) do
      Respond.ok(conn, account, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, account} <- Banking.update(company_id, id, params) do
      Respond.ok(conn, account)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Banking.delete(company_id, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Транзакции

  def transactions(conn, params) do
    with {:ok, company_id} <- active(conn) do
      company_id |> Tx.index(params) |> Render.page(params) |> then(&Respond.ok(conn, &1))
    else
      error -> Respond.error(conn, error)
    end
  end

  def preview(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Tx.preview(company_id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def import(conn, params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Tx.import(company_id, conn.assigns.current_user.username, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def book_preview(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Tx.book_preview(company_id, id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def book(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Tx.book(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def reallocate(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Tx.reallocate(company_id, conn.assigns.current_user.username, id, params) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete_transaction(conn, %{"id" => id}) do
    with {:ok, company_id} <- active(conn),
         {:ok, nil} <- Tx.delete(company_id, conn.assigns.current_user.username, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def bulk_delete_transactions(conn, params) do
    with {:ok, company_id} <- active(conn) do
      ids = params |> Map.get("ids", []) |> Enum.filter(&is_integer/1)
      Respond.ok(conn, Tx.bulk_delete(company_id, conn.assigns.current_user.username, ids))
    else
      error -> Respond.error(conn, error)
    end
  end

  ## Правила

  def rules(conn, _params) do
    with {:ok, company_id} <- active(conn) do
      Respond.ok(conn, %{items: Rules.index(company_id)})
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

  def update_rule(conn, %{"id" => id} = params) do
    with {:ok, company_id} <- active(conn),
         {:ok, rule} <- Rules.update(company_id, id, params) do
      Respond.ok(conn, rule)
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

  def rule_defaults(conn, _params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Rules.defaults(company_id) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def auto_allocate(conn, _params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Rules.auto_allocate(company_id, conn.assigns.current_user.username) do
      Respond.ok(conn, data)
    else
      error -> Respond.error(conn, error)
    end
  end

  def allocate_preview(conn, _params) do
    with {:ok, company_id} <- active(conn),
         {:ok, data} <- Rules.preview(company_id, conn.assigns.current_user.username) do
      Respond.ok(conn, data)
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

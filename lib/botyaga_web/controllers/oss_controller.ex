defmodule BotyagaWeb.OssController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Oss}
  alias Botyaga.Oss.Rates
  alias BotyagaWeb.Respond

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, id} when id > 0 -> {:ok, id}
      _ -> {:error, {422, "няма активна фирма"}}
    end
  end

  defp sub(conn), do: conn.assigns.current_user.username

  def reports(conn, _params) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{items: Oss.list(cid)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def report(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.get(cid, id) do
      Respond.ok(conn, r)
    else
      error -> Respond.error(conn, error)
    end
  end

  def create(conn, params) do
    with {:ok, cid} <- active(conn),
         {:ok, r} <- Oss.create(cid, params) do
      Respond.ok(conn, r, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, r} <- Oss.update(cid, id, params) do
      Respond.ok(conn, r)
    else
      error -> Respond.error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, _} <- Oss.delete(cid, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def preview(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, p} <- Oss.preview(cid, id) do
      Respond.ok(conn, p)
    else
      error -> Respond.error(conn, error)
    end
  end

  def confirm(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.confirm(cid, id) do
      Respond.ok(conn, r)
    else
      error -> Respond.error(conn, error)
    end
  end

  def unpost(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.unpost(cid, id) do
      Respond.ok(conn, r)
    else
      error -> Respond.error(conn, error)
    end
  end

  def month(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{
        month: month,
        base: Botyaga.Dec.money(Oss.month_base(cid, month)),
        declared: Oss.declared_invoice(cid, month) != nil
      })
    else
      error -> Respond.error(conn, error)
    end
  end

  def declare(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn),
         {:ok, inv} <- Oss.declare_month(cid, sub(conn), month) do
      Respond.ok(conn, inv)
    else
      error -> Respond.error(conn, error)
    end
  end

  def undeclare(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn),
         {:ok, _} <- Oss.undeclare_month(cid, sub(conn), month) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def quarter(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.quarter(cid, String.to_integer(y), String.to_integer(q)) do
      Respond.ok(conn, d)
    else
      error -> Respond.error(conn, error)
    end
  end

  def freeze(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.freeze(cid, String.to_integer(y), String.to_integer(q)) do
      Respond.ok(conn, d)
    else
      error -> Respond.error(conn, error)
    end
  end

  def submit(conn, %{"year" => y, "quarter" => q} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.submit(cid, String.to_integer(y), String.to_integer(q), params) do
      Respond.ok(conn, d)
    else
      error -> Respond.error(conn, error)
    end
  end

  def unsubmit(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.unsubmit(cid, String.to_integer(y), String.to_integer(q)) do
      Respond.ok(conn, d)
    else
      error -> Respond.error(conn, error)
    end
  end

  ## ДДС ставки по държави (история)

  def rates(conn, _params) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{items: Rates.list(cid)})
    else
      error -> Respond.error(conn, error)
    end
  end

  def rate_create(conn, params) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Rates.create(cid, params) do
      Respond.ok(conn, r, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def rate_copy(conn, %{"id" => id} = params) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Rates.copy(cid, id, params) do
      Respond.ok(conn, r, 201)
    else
      error -> Respond.error(conn, error)
    end
  end

  def rate_delete(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, _} <- Rates.delete(cid, id) do
      Respond.no_content(conn)
    else
      error -> Respond.error(conn, error)
    end
  end

  def register(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{
        items: Oss.register(cid, String.to_integer(y), String.to_integer(q))
      })
    else
      error -> Respond.error(conn, error)
    end
  end
end

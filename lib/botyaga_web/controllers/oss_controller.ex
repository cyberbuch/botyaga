defmodule BotyagaWeb.OssController do
  use BotyagaWeb, :controller

  alias Botyaga.{Companies, Oss}
  alias BotyagaWeb.Respond

  defp active(conn) do
    case Companies.resolve_active(conn.assigns.current_user.username) do
      {:ok, id} when id > 0 -> {:ok, id}
      _ -> {:error, {422, "няма активна фирма"}}
    end
  end

  defp sub(conn), do: conn.assigns.current_user.username

  def reports(conn, _params) do
    with {:ok, cid} <- active(conn), do: Respond.ok(conn, %{items: Oss.list(cid)})
  end

  def report(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.get(cid, id), do: Respond.ok(conn, r)
  end

  def create(conn, params) do
    with {:ok, cid} <- active(conn),
         {:ok, r} <- Oss.create(cid, params),
         do: Respond.ok(conn, r, 201)
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, r} <- Oss.update(cid, id, params),
         do: Respond.ok(conn, r)
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, _} <- Oss.delete(cid, id), do: Respond.no_content(conn)
  end

  def preview(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, p} <- Oss.preview(cid, id), do: Respond.ok(conn, p)
  end

  def confirm(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.confirm(cid, id), do: Respond.ok(conn, r)
  end

  def unpost(conn, %{"id" => id}) do
    with {:ok, cid} <- active(conn), {:ok, r} <- Oss.unpost(cid, id), do: Respond.ok(conn, r)
  end

  def month(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn) do
      Respond.ok(conn, %{
        month: month,
        base: Botyaga.Dec.money(Oss.month_base(cid, month)),
        declared: Oss.declared_invoice(cid, month) != nil
      })
    end
  end

  def declare(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn),
         {:ok, inv} <- Oss.declare_month(cid, sub(conn), month),
         do: Respond.ok(conn, inv)
  end

  def undeclare(conn, %{"month" => month}) do
    with {:ok, cid} <- active(conn),
         {:ok, _} <- Oss.undeclare_month(cid, sub(conn), month),
         do: Respond.no_content(conn)
  end

  def quarter(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.quarter(cid, String.to_integer(y), String.to_integer(q)),
         do: Respond.ok(conn, d)
  end

  def freeze(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.freeze(cid, String.to_integer(y), String.to_integer(q)),
         do: Respond.ok(conn, d)
  end

  def submit(conn, %{"year" => y, "quarter" => q} = params) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.submit(cid, String.to_integer(y), String.to_integer(q), params),
         do: Respond.ok(conn, d)
  end

  def unsubmit(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         {:ok, d} <- Oss.unsubmit(cid, String.to_integer(y), String.to_integer(q)),
         do: Respond.ok(conn, d)
  end

  def register(conn, %{"year" => y, "quarter" => q}) do
    with {:ok, cid} <- active(conn),
         do:
           Respond.ok(conn, %{
             items: Oss.register(cid, String.to_integer(y), String.to_integer(q))
           })
  end
end

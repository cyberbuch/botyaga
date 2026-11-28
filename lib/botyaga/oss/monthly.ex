defmodule Botyaga.Oss.Monthly do
  @moduledoc """
  Месечно деклариране на OSS доставките в дневника за продажби
  (документ вид 81, колона 23 → клетка 18 на ДДС декларацията).
  """

  import Ecto.Query

  alias Botyaga.{Dec, Invoicing, Repo}
  alias Botyaga.Invoicing.Post
  alias Botyaga.Oss.{Internal, Report}

  ## Месечно деклариране (вид 81, колона 23)

  def month_base(company_id, month) do
    reports =
      Repo.all(
        from(r in Report,
          where: r.company_id == ^company_id and r.month == ^month and r.status == "active"
        )
      )
      |> Enum.reduce(0, fn r, acc ->
        acc + Internal.sum(Internal.lines_of(r.id), & &1.base_eur)
      end)

    invoices =
      Repo.all(
        from(i in Invoicing.Invoice,
          where:
            i.company_id == ^company_id and i.is_oss == 1 and i.status == "posted" and
              i.document_type != "81" and like(i.issue_date, ^"#{month}%")
        )
      )
      |> Enum.reduce(0, fn i, acc -> acc + (Dec.or0(i.net_amount) || 0) end)

    reports + invoices
  end

  def declared_invoice(company_id, month) do
    Repo.get_by(Invoicing.Invoice,
      company_id: company_id,
      is_oss: 1,
      document_type: "81",
      accounting_month: month
    )
  end

  def declare_month(company_id, sub, month) do
    case declared_invoice(company_id, month) do
      nil ->
        base = month_base(company_id, month)
        cp = Internal.population(company_id)
        product = Internal.oss_product(company_id)
        last = Internal.last_day(month)

        with {:ok, inv} <-
               Invoicing.create(company_id, sub, %{
                 "direction" => "out",
                 "document_type" => "81",
                 "number" => "OSS-DECL-#{month}",
                 "issue_date" => last,
                 "accounting_month" => month,
                 "counterpart_id" => cp.id,
                 "is_oss" => 1,
                 "lines" => [
                   %{
                     "product_id" => product.id,
                     "description" => "OSS доставки за #{month}",
                     "quantity" => "1",
                     "unit_price" => Dec.money(base),
                     "vat_rate" => "0",
                     "net_amount" => Dec.money(base),
                     "vat_amount" => "0",
                     "total_amount" => Dec.money(base)
                   }
                 ]
               }),
             id = inv[:id] || inv["id"],
             {:ok, posted} <- Post.post(company_id, sub, id) do
          {:ok, posted}
        end

      inv ->
        {:ok, inv}
    end
  end

  def undeclare_month(company_id, sub, month) do
    case declared_invoice(company_id, month) do
      nil ->
        {:error, {404, "месецът не е деклариран"}}

      inv ->
        with {:ok, _} <- Post.unpost(company_id, sub, inv.id),
             {:ok, _} <- Invoicing.delete(company_id, sub, inv.id) do
          {:ok, nil}
        end
    end
  end
end

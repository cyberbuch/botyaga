defmodule Botyaga.Oss.Quarter do
  @moduledoc """
  Тримесечна справка-декларация по чл.159 ЗДДС (Приложение 32):
  регистър на OSS доставките, замразяване и подаване.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Invoicing, Repo}
  alias Botyaga.Oss.{Declaration, Internal, Report}

  ## Тримесечна справка-декларация (чл.159)

  def quarter(company_id, year, q) do
    case Repo.get_by(Declaration, company_id: company_id, year: year, quarter: q) do
      nil ->
        {:ok, %{status: "draft", data: compute_quarter(company_id, year, q)}}

      d ->
        data =
          if d.frozen, do: Jason.decode!(d.frozen), else: compute_quarter(company_id, year, q)

        {:ok,
         %{
           status: d.status,
           submitted_at: d.submitted_at,
           submission_no: d.submission_no,
           data: data
         }}
    end
  end

  def freeze(company_id, year, q) do
    data = compute_quarter(company_id, year, q)

    {:ok, d} =
      case Repo.get_by(Declaration, company_id: company_id, year: year, quarter: q) do
        nil ->
          Repo.insert(%Declaration{
            company_id: company_id,
            year: year,
            quarter: q,
            status: "final",
            frozen: Jason.encode!(data)
          })

        d ->
          Repo.update(Ecto.Changeset.change(d, status: "final", frozen: Jason.encode!(data)))
      end

    {:ok, %{status: d.status, data: data}}
  end

  def submit(company_id, year, q, params) do
    with {:ok, d} <- Internal.fetch_declaration(company_id, year, q),
         true <- d.status == "final" do
      {:ok, d} =
        Repo.update(
          Ecto.Changeset.change(d,
            status: "submitted",
            submitted_at: Internal.str(params, "date"),
            submission_no: Internal.str(params, "number")
          )
        )

      {:ok, %{status: d.status}}
    else
      false -> {:error, {422, "първо изгответе справката"}}
      error -> error
    end
  end

  def unsubmit(company_id, year, q) do
    with {:ok, d} <- Internal.fetch_declaration(company_id, year, q) do
      {:ok, d} =
        Repo.update(
          Ecto.Changeset.change(d, status: "final", submitted_at: "", submission_no: "")
        )

      {:ok, %{status: d.status}}
    end
  end

  defp compute_quarter(company_id, year, q) do
    rows = register(company_id, year, q)
    {m1, m2, m3} = Internal.quarter_months(q)

    months =
      MapSet.new([
        "#{year}-#{Internal.pad(m1)}",
        "#{year}-#{Internal.pad(m2)}",
        "#{year}-#{Internal.pad(m3)}"
      ])

    current = Enum.filter(rows, &MapSet.member?(months, &1.month))

    corrections =
      Enum.filter(rows, &(&1.correction_quarter != "" and not MapSet.member?(months, &1.month)))

    part2a = Enum.filter(current, &(&1.supply_kind == "services"))
    part2b = Enum.filter(current, &(&1.supply_kind == "goods"))

    by_country =
      current
      |> Enum.group_by(& &1.country)
      |> Enum.map(fn {c, ls} ->
        %{country: c, vat_eur: Dec.money(Internal.sum(ls, & &1.vat_eur))}
      end)
      |> Enum.sort_by(& &1.country)

    total =
      by_country
      |> Enum.filter(&(Dec.or0(&1.vat_eur) > 0))
      |> Enum.reduce(0, &(&2 + Dec.or0(&1.vat_eur)))

    %{
      year: year,
      quarter: q,
      part2a: group_rows(part2a),
      part2b: group_rows(part2b),
      part3: group_rows(corrections),
      part4: by_country,
      part5_total: Dec.money(total)
    }
  end

  defp group_rows(rows) do
    rows
    |> Enum.group_by(fn r -> {r.country, r.supply_kind, r.rate_kind, r.rate} end)
    |> Enum.map(fn {{c, sk, rk, rate}, ls} ->
      %{
        country: c,
        supply_kind: sk,
        rate_kind: rk,
        rate: rate,
        base_eur: Dec.money(Internal.sum(ls, & &1.base_eur)),
        vat_eur: Dec.money(Internal.sum(ls, & &1.vat_eur))
      }
    end)
    |> Enum.sort_by(& &1.country)
  end

  @doc "Регистър на OSS доставките (отчети + фактури) за тримесечие."
  def register(company_id, year, q) do
    {m1, _, m3} = Internal.quarter_months(q)
    from = "#{year}-#{Internal.pad(m1)}-01"
    to = Internal.last_day("#{year}-#{Internal.pad(m3)}")

    reports =
      Repo.all(
        from(r in Report,
          where:
            r.company_id == ^company_id and r.status == "active" and r.doc_date >= ^from and
              r.doc_date <= ^to
        )
      )

    report_rows =
      Enum.flat_map(reports, fn r ->
        Enum.map(Internal.lines_of(r.id), fn l ->
          %{
            month: r.month,
            doc: r.number,
            country: l.country,
            supply_kind: l.supply_kind,
            rate_kind: l.rate_kind,
            rate: l.rate,
            base_eur: l.base_eur,
            vat_eur: l.vat_eur,
            correction_quarter: r.correction_quarter
          }
        end)
      end)

    invoices =
      Repo.all(
        from(i in Invoicing.Invoice,
          where:
            i.company_id == ^company_id and i.is_oss == 1 and i.status == "posted" and
              i.document_type != "81" and i.issue_date >= ^from and i.issue_date <= ^to
        )
      )
      |> Enum.map(fn i ->
        %{
          month: String.slice(i.issue_date, 0, 7),
          doc: i.number,
          country: i.oss_country,
          supply_kind: "goods",
          rate_kind: "standard",
          rate: "0",
          base_eur: i.net_amount,
          vat_eur: i.vat_amount,
          correction_quarter: ""
        }
      end)

    report_rows ++ invoices
  end
end

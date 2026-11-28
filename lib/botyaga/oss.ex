defmodule Botyaga.Oss do
  @moduledoc """
  OSS режим в Съюза (чл.156 ЗДДС): отчети за доставки по чл.119, ал.5,
  месечно деклариране в дневника с вид 81 (колона 23 → клетка 18) и тримесечна
  справка-декларация по чл.159 (Приложение 32). Порт на CONTROLISY OSS.

  Месечното деклариране живее в `Botyaga.Oss.Monthly`, тримесечната
  справка-декларация — в `Botyaga.Oss.Quarter`, а споделените помощници —
  в `Botyaga.Oss.Internal`.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Journal, Params, Repo}
  alias Botyaga.Oss.{Internal, Monthly, Quarter, Report, ReportLine}

  ## Отчети

  def list(company_id) do
    Repo.all(from(r in Report, where: r.company_id == ^company_id, order_by: [desc: r.id]))
    |> Enum.map(&Internal.one(&1, false))
  end

  def get(company_id, id) do
    case Repo.get_by(Report, id: id, company_id: company_id) do
      nil -> {:error, {404, "отчетът не е намерен"}}
      r -> {:ok, Internal.one(r, true)}
    end
  end

  def create(company_id, params) do
    with {:ok, month} <- Internal.month_param(params),
         {:ok, date} <- Internal.date_param(params, month) do
      number = Internal.next_number(company_id, date)

      {:ok, r} =
        Repo.insert(%Report{
          company_id: company_id,
          number: number,
          doc_date: date,
          month: month,
          status: "draft",
          correction_of_id: Params.integer(params, "correction_of_id") || 0,
          correction_quarter: Internal.str(params, "correction_quarter"),
          notes: Internal.str(params, "notes")
        })

      Internal.insert_lines(r.id, params)
      get(company_id, r.id)
    end
  end

  def update(company_id, id, params) do
    with {:ok, r} <- Internal.fetch_draft(company_id, id) do
      {:ok, r} =
        Repo.update(
          Ecto.Changeset.change(r,
            notes: Internal.pick(params, "notes", r.notes),
            correction_quarter: Internal.pick(params, "correction_quarter", r.correction_quarter)
          )
        )

      if Map.has_key?(params, "lines") do
        Repo.delete_all(from(l in ReportLine, where: l.report_id == ^r.id))
        Internal.insert_lines(r.id, params)
      end

      get(company_id, r.id)
    end
  end

  def delete(company_id, id) do
    with {:ok, r} <- Internal.fetch_draft(company_id, id) do
      Repo.delete!(r)
      {:ok, nil}
    end
  end

  @doc "Преглед „всичко или нищо“: грешни редове + обобщение по държава/вид/ставка."
  def preview(company_id, id) do
    with {:ok, r} <- Internal.fetch(company_id, id) do
      lines = Internal.lines_of(r.id)
      errors = Internal.validate_lines(lines, r.month)

      summary =
        lines
        |> Enum.group_by(fn l -> {l.country, l.supply_kind, l.rate_kind, l.rate} end)
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

      {:ok,
       %{
         errors: errors,
         summary: summary,
         total_base: Dec.money(Internal.sum(lines, & &1.base_eur)),
         total_vat: Dec.money(Internal.sum(lines, & &1.vat_eur))
       }}
    end
  end

  def confirm(company_id, id) do
    with {:ok, r} <- Internal.fetch_draft(company_id, id),
         {:ok, pv} <- preview(company_id, id),
         :ok <- Internal.no_errors(pv),
         :ok <- Internal.month_unlocked(company_id, r.month) do
      lines = Internal.lines_of(r.id)

      sides =
        Enum.flat_map(lines, fn l ->
          with {:ok, rev} <- Internal.account(company_id, l.account),
               {:ok, cust} <- Internal.account(company_id, "411"),
               {:ok, oss} <- Internal.account(company_id, "4534") do
            [
              %{account: cust, direction: "debit", amount: l.gross_eur},
              %{account: rev, direction: "credit", amount: l.base_eur},
              %{account: oss, direction: "credit", amount: l.vat_eur}
            ]
          else
            _ -> []
          end
        end)

      {:ok, eid} =
        Journal.write_entry(
          company_id,
          r.doc_date,
          "oss_report",
          r.id,
          r.number,
          "OSS отчет #{r.number}",
          0,
          "",
          r.month,
          sides
        )

      Repo.update!(Ecto.Changeset.change(r, status: "active", journal_entry_id: eid))
      get(company_id, id)
    end
  end

  def unpost(company_id, id) do
    with {:ok, r} <- Internal.fetch_active(company_id, id),
         :ok <- Internal.month_unlocked(company_id, r.month) do
      Journal.wipe(r.journal_entry_id)
      Repo.update!(Ecto.Changeset.change(r, status: "draft", journal_entry_id: 0))
      get(company_id, id)
    end
  end

  ## Месечно деклариране (вид 81, колона 23)

  def month_base(company_id, month), do: Monthly.month_base(company_id, month)

  def declared_invoice(company_id, month), do: Monthly.declared_invoice(company_id, month)

  def declare_month(company_id, sub, month), do: Monthly.declare_month(company_id, sub, month)

  def undeclare_month(company_id, sub, month), do: Monthly.undeclare_month(company_id, sub, month)

  ## Тримесечна справка-декларация (чл.159)

  def quarter(company_id, year, q), do: Quarter.quarter(company_id, year, q)

  def freeze(company_id, year, q), do: Quarter.freeze(company_id, year, q)

  def submit(company_id, year, q, params), do: Quarter.submit(company_id, year, q, params)

  def unsubmit(company_id, year, q), do: Quarter.unsubmit(company_id, year, q)

  @doc "Регистър на OSS доставките (отчети + фактури) за тримесечие."
  def register(company_id, year, q), do: Quarter.register(company_id, year, q)
end

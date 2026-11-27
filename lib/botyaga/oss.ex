defmodule Botyaga.Oss do
  @moduledoc """
  OSS режим в Съюза (чл.156 ЗДДС): отчети за доставки по чл.119, ал.5,
  месечно деклариране в дневника с вид 81 (колона 23 → клетка 18) и тримесечна
  справка-декларация по чл.159 (Приложение 32). Порт на CONTROLISY OSS.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Invoicing, Journal, Params, Repo}
  alias Botyaga.Invoicing.Post
  alias Botyaga.Oss.{Declaration, Report, ReportLine}

  @accounts ~w(701 702 703 706 709)

  ## Отчети

  def list(company_id) do
    Repo.all(from(r in Report, where: r.company_id == ^company_id, order_by: [desc: r.id]))
    |> Enum.map(&one(&1, false))
  end

  def get(company_id, id) do
    case Repo.get_by(Report, id: id, company_id: company_id) do
      nil -> {:error, {404, "отчетът не е намерен"}}
      r -> {:ok, one(r, true)}
    end
  end

  def create(company_id, params) do
    with {:ok, month} <- month_param(params),
         {:ok, date} <- date_param(params, month) do
      number = next_number(company_id, date)

      {:ok, r} =
        Repo.insert(%Report{
          company_id: company_id,
          number: number,
          doc_date: date,
          month: month,
          status: "draft",
          correction_of_id: Params.integer(params, "correction_of_id") || 0,
          correction_quarter: str(params, "correction_quarter"),
          notes: str(params, "notes")
        })

      insert_lines(r.id, params)
      get(company_id, r.id)
    end
  end

  def update(company_id, id, params) do
    with {:ok, r} <- fetch_draft(company_id, id) do
      {:ok, r} =
        Repo.update(
          Ecto.Changeset.change(r,
            notes: pick(params, "notes", r.notes),
            correction_quarter: pick(params, "correction_quarter", r.correction_quarter)
          )
        )

      if Map.has_key?(params, "lines") do
        Repo.delete_all(from(l in ReportLine, where: l.report_id == ^r.id))
        insert_lines(r.id, params)
      end

      get(company_id, r.id)
    end
  end

  def delete(company_id, id) do
    with {:ok, r} <- fetch_draft(company_id, id) do
      Repo.delete!(r)
      {:ok, nil}
    end
  end

  @doc "Преглед „всичко или нищо“: грешни редове + обобщение по държава/вид/ставка."
  def preview(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      lines = lines_of(r.id)
      errors = validate_lines(lines, r.month)

      summary =
        lines
        |> Enum.group_by(fn l -> {l.country, l.supply_kind, l.rate_kind, l.rate} end)
        |> Enum.map(fn {{c, sk, rk, rate}, ls} ->
          %{
            country: c,
            supply_kind: sk,
            rate_kind: rk,
            rate: rate,
            base_eur: Dec.money(sum(ls, & &1.base_eur)),
            vat_eur: Dec.money(sum(ls, & &1.vat_eur))
          }
        end)
        |> Enum.sort_by(& &1.country)

      {:ok,
       %{
         errors: errors,
         summary: summary,
         total_base: Dec.money(sum(lines, & &1.base_eur)),
         total_vat: Dec.money(sum(lines, & &1.vat_eur))
       }}
    end
  end

  def confirm(company_id, id) do
    with {:ok, r} <- fetch_draft(company_id, id),
         {:ok, pv} <- preview(company_id, id),
         :ok <- no_errors(pv),
         :ok <- month_unlocked(company_id, r.month) do
      lines = lines_of(r.id)

      sides =
        Enum.flat_map(lines, fn l ->
          with {:ok, rev} <- account(company_id, l.account),
               {:ok, cust} <- account(company_id, "411"),
               {:ok, oss} <- account(company_id, "4534") do
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
    with {:ok, r} <- fetch_active(company_id, id),
         :ok <- month_unlocked(company_id, r.month) do
      Journal.wipe(r.journal_entry_id)
      Repo.update!(Ecto.Changeset.change(r, status: "draft", journal_entry_id: 0))
      get(company_id, id)
    end
  end

  ## Месечно деклариране (вид 81, колона 23)

  def month_base(company_id, month) do
    reports =
      Repo.all(
        from(r in Report,
          where: r.company_id == ^company_id and r.month == ^month and r.status == "active"
        )
      )
      |> Enum.reduce(0, fn r, acc -> acc + sum(lines_of(r.id), & &1.base_eur) end)

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
        cp = population(company_id)
        product = oss_product(company_id)
        last = last_day(month)

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
    with {:ok, d} <- fetch_declaration(company_id, year, q),
         true <- d.status == "final" do
      {:ok, d} =
        Repo.update(
          Ecto.Changeset.change(d,
            status: "submitted",
            submitted_at: str(params, "date"),
            submission_no: str(params, "number")
          )
        )

      {:ok, %{status: d.status}}
    else
      false -> {:error, {422, "първо изгответе справката"}}
      error -> error
    end
  end

  def unsubmit(company_id, year, q) do
    with {:ok, d} <- fetch_declaration(company_id, year, q) do
      {:ok, d} =
        Repo.update(
          Ecto.Changeset.change(d, status: "final", submitted_at: "", submission_no: "")
        )

      {:ok, %{status: d.status}}
    end
  end

  defp compute_quarter(company_id, year, q) do
    rows = register(company_id, year, q)
    {m1, m2, m3} = quarter_months(q)
    months = MapSet.new(["#{year}-#{pad(m1)}", "#{year}-#{pad(m2)}", "#{year}-#{pad(m3)}"])

    current = Enum.filter(rows, &MapSet.member?(months, &1.month))

    corrections =
      Enum.filter(rows, &(&1.correction_quarter != "" and not MapSet.member?(months, &1.month)))

    part2a = Enum.filter(current, &(&1.supply_kind == "services"))
    part2b = Enum.filter(current, &(&1.supply_kind == "goods"))

    by_country =
      current
      |> Enum.group_by(& &1.country)
      |> Enum.map(fn {c, ls} -> %{country: c, vat_eur: Dec.money(sum(ls, & &1.vat_eur))} end)
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
        base_eur: Dec.money(sum(ls, & &1.base_eur)),
        vat_eur: Dec.money(sum(ls, & &1.vat_eur))
      }
    end)
    |> Enum.sort_by(& &1.country)
  end

  @doc "Регистър на OSS доставките (отчети + фактури) за тримесечие."
  def register(company_id, year, q) do
    {m1, _, m3} = quarter_months(q)
    from = "#{year}-#{pad(m1)}-01"
    to = last_day("#{year}-#{pad(m3)}")

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
        Enum.map(lines_of(r.id), fn l ->
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

  ## Вътрешни

  defp fetch(company_id, id), do: Repo.get_by(Report, id: id, company_id: company_id) |> ok404()

  defp fetch_draft(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      if r.status == "draft",
        do: {:ok, r},
        else: {:error, {422, "активен отчет не се променя — изтрийте го и създайте нов"}}
    end
  end

  defp fetch_active(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      if r.status == "active", do: {:ok, r}, else: {:error, {422, "отчетът не е активен"}}
    end
  end

  defp fetch_declaration(company_id, year, q) do
    case Repo.get_by(Declaration, company_id: company_id, year: year, quarter: q) do
      nil -> {:error, {404, "няма справка за това тримесечие"}}
      d -> {:ok, d}
    end
  end

  defp ok404(nil), do: {:error, {404, "отчетът не е намерен"}}
  defp ok404(r), do: {:ok, r}

  defp month_unlocked(company_id, month) do
    if declared_invoice(company_id, month),
      do:
        {:error,
         {422,
          "месецът е деклариран в дневника — изтрийте декларирането, за да променяте отчетите"}},
      else: :ok
  end

  defp no_errors(%{errors: []}), do: :ok
  defp no_errors(_), do: {:error, {422, "прегледът има грешки — поправете ги преди създаване"}}

  defp validate_lines(lines, month) do
    Enum.flat_map(lines, fn l ->
      errs = []

      errs =
        if l.account not in @accounts,
          do: ["сметка #{l.account} не е 701/702/703/706/709" | errs],
          else: errs

      errs = if l.country == "", do: ["липсва държава" | errs], else: errs
      errs = if Dec.or0(l.gross_eur) == 0, do: ["сума 0" | errs], else: errs

      errs =
        if l.delivery_date != "" and not String.starts_with?(l.delivery_date, month),
          do: ["дата извън месеца" | errs],
          else: errs

      Enum.map(errs, fn e -> %{line: l.id, error: e} end)
    end)
  end

  defp insert_lines(report_id, params) do
    arr = Map.get(params, "lines") || []

    Enum.each(arr, fn l ->
      rate = str(l, "rate")
      gross = str(l, "gross")
      fx = pick(l, "fx", "1")
      currency = pick(l, "currency", "EUR")

      gross_eur =
        if currency == "EUR", do: Dec.or0(gross), else: Dec.mul(Dec.or0(gross), Dec.or0(fx))

      hundred = 100 * Dec.scale()
      base = Dec.div(Dec.mul(gross_eur, hundred), hundred + Dec.or0(rate)) || 0
      vat = gross_eur - base

      %ReportLine{}
      |> Ecto.Changeset.change(%{
        report_id: report_id,
        account: pick(l, "account", "702"),
        country: str(l, "country"),
        supply_kind: pick(l, "supply_kind", "goods"),
        rate_kind: pick(l, "rate_kind", "standard"),
        rate: rate,
        gross: gross,
        currency: currency,
        fx: fx,
        gross_eur: Dec.money(gross_eur),
        base_eur: Dec.money(base),
        vat_eur: Dec.money(vat),
        quantity: str(l, "quantity"),
        order_no: str(l, "order_no"),
        description: str(l, "description"),
        delivery_date: str(l, "delivery_date")
      })
      |> Repo.insert!()
    end)
  end

  defp lines_of(report_id),
    do: Repo.all(from(l in ReportLine, where: l.report_id == ^report_id, order_by: [asc: l.id]))

  defp one(r, with_lines) do
    base = %{
      id: r.id,
      number: r.number,
      doc_date: r.doc_date,
      month: r.month,
      status: r.status,
      correction_of_id: r.correction_of_id,
      correction_quarter: r.correction_quarter,
      notes: r.notes,
      journal_entry_id: r.journal_entry_id
    }

    if with_lines, do: Map.put(base, :lines, Enum.map(lines_of(r.id), &line_json/1)), else: base
  end

  defp line_json(l) do
    %{
      id: l.id,
      account: l.account,
      country: l.country,
      supply_kind: l.supply_kind,
      rate_kind: l.rate_kind,
      rate: l.rate,
      gross: l.gross,
      currency: l.currency,
      fx: l.fx,
      gross_eur: l.gross_eur,
      base_eur: l.base_eur,
      vat_eur: l.vat_eur,
      quantity: l.quantity,
      order_no: l.order_no,
      description: l.description,
      delivery_date: l.delivery_date
    }
  end

  defp sum(lines, fun), do: Enum.reduce(lines, 0, fn l, acc -> acc + Dec.or0(fun.(l)) end)

  defp account(company_id, number) do
    case Repo.get_by(Catalog.Account, company_id: company_id, number: number) do
      nil ->
        {:ok, a} =
          Repo.insert(%Catalog.Account{
            company_id: company_id,
            number: number,
            name: account_name(number)
          })

        {:ok, a}

      a ->
        {:ok, a}
    end
  end

  defp account_name("4534"), do: "ДДС по OSS режим"
  defp account_name("411"), do: "Вземания от клиенти"
  defp account_name(n), do: "Приходи от продажби #{n}"

  defp population(company_id) do
    case Repo.get_by(Catalog.Counterpart, company_id: company_id, name: "Население") do
      nil ->
        Repo.insert!(%Catalog.Counterpart{
          company_id: company_id,
          name: "Население",
          eik: "999999999"
        })

      c ->
        c
    end
  end

  defp oss_product(company_id) do
    case Repo.get_by(Catalog.Product, company_id: company_id, name: "OSS доставки") do
      nil ->
        Repo.insert!(%Catalog.Product{
          company_id: company_id,
          name: "OSS доставки",
          product_type: "30",
          is_inventory: 0
        })

      p ->
        p
    end
  end

  defp next_number(company_id, date) do
    d = String.slice(date, 8, 2)
    m = String.slice(date, 5, 2)
    y = String.slice(date, 0, 4)
    base = "OSS-#{d}.#{m}.#{y}"

    n =
      Repo.aggregate(
        from(r in Report, where: r.company_id == ^company_id and like(r.number, ^"#{base}%")),
        :count,
        :id
      )

    if n == 0, do: base, else: "#{base}/#{n + 1}"
  end

  defp month_param(params) do
    case str(params, "month") do
      m when byte_size(m) == 7 -> {:ok, m}
      _ -> {:error, {422, "month е задължителен (YYYY-MM)"}}
    end
  end

  defp date_param(params, month) do
    case str(params, "doc_date") do
      "" -> {:ok, last_day(month)}
      d -> {:ok, d}
    end
  end

  defp last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    Date.to_iso8601(Date.end_of_month(Date.new!(y, m, 1)))
  end

  defp quarter_months(1), do: {1, 2, 3}
  defp quarter_months(2), do: {4, 5, 6}
  defp quarter_months(3), do: {7, 8, 9}
  defp quarter_months(4), do: {10, 11, 12}

  defp pad(n), do: Integer.to_string(n) |> String.pad_leading(2, "0")

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> ""
    end
  end

  defp pick(params, key, default) do
    case str(params, key) do
      "" -> default
      v -> v
    end
  end
end

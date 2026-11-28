defmodule Botyaga.Oss.Internal do
  @moduledoc """
  Споделени помощници на OSS модулите (`Botyaga.Oss`, `Botyaga.Oss.Monthly`,
  `Botyaga.Oss.Quarter`): достъп до отчети и справки-декларации, редове,
  валидации, номерация и параметри.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Params, Repo}
  alias Botyaga.Oss.{Declaration, Monthly, Report, ReportLine}

  @accounts ~w(701 702 703 706 709)

  ## Вътрешни

  def fetch(company_id, id), do: Repo.get_by(Report, id: id, company_id: company_id) |> ok404()

  def fetch_draft(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      if r.status == "draft",
        do: {:ok, r},
        else: {:error, {422, "активен отчет не се променя — изтрийте го и създайте нов"}}
    end
  end

  def fetch_active(company_id, id) do
    with {:ok, r} <- fetch(company_id, id) do
      if r.status == "active", do: {:ok, r}, else: {:error, {422, "отчетът не е активен"}}
    end
  end

  def fetch_declaration(company_id, year, q) do
    case Repo.get_by(Declaration, company_id: company_id, year: year, quarter: q) do
      nil -> {:error, {404, "няма справка за това тримесечие"}}
      d -> {:ok, d}
    end
  end

  def ok404(nil), do: {:error, {404, "отчетът не е намерен"}}
  def ok404(r), do: {:ok, r}

  def month_unlocked(company_id, month) do
    if Monthly.declared_invoice(company_id, month),
      do:
        {:error,
         {422,
          "месецът е деклариран в дневника — изтрийте декларирането, за да променяте отчетите"}},
      else: :ok
  end

  def no_errors(%{errors: []}), do: :ok
  def no_errors(_), do: {:error, {422, "прегледът има грешки — поправете ги преди създаване"}}

  def validate_lines(lines, month) do
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

  def insert_lines(report_id, params) do
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

  def lines_of(report_id),
    do: Repo.all(from(l in ReportLine, where: l.report_id == ^report_id, order_by: [asc: l.id]))

  def one(r, with_lines) do
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

  def line_json(l) do
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

  def sum(lines, fun), do: Enum.reduce(lines, 0, fn l, acc -> acc + Dec.or0(fun.(l)) end)

  def account(company_id, number) do
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

  def account_name("4534"), do: "ДДС по OSS режим"
  def account_name("411"), do: "Вземания от клиенти"
  def account_name(n), do: "Приходи от продажби #{n}"

  def population(company_id) do
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

  def oss_product(company_id) do
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

  def next_number(company_id, date) do
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

  def month_param(params) do
    case str(params, "month") do
      m when byte_size(m) == 7 -> {:ok, m}
      _ -> {:error, {422, "month е задължителен (YYYY-MM)"}}
    end
  end

  def date_param(params, month) do
    case str(params, "doc_date") do
      "" -> {:ok, last_day(month)}
      d -> {:ok, d}
    end
  end

  def last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    Date.to_iso8601(Date.end_of_month(Date.new!(y, m, 1)))
  end

  def quarter_months(1), do: {1, 2, 3}
  def quarter_months(2), do: {4, 5, 6}
  def quarter_months(3), do: {7, 8, 9}
  def quarter_months(4), do: {10, 11, 12}

  def pad(n), do: Integer.to_string(n) |> String.pad_leading(2, "0")

  def str(params, key) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> ""
    end
  end

  def pick(params, key, default) do
    case str(params, key) do
      "" -> default
      v -> v
    end
  end
end

defmodule Botyaga.Saft do
  @moduledoc """
  GET /v1/saft/export по BG_SAFT_Schema V1.0.1. Заглавката носи Ownership, контакт
  и IBAN. Месец без банково плащане пак пише Payments с нула записа. Порт на
  `saft_export.rs`: месечен, годишен и при поискване (с дати от-до).
  """

  alias Botyaga.Dec
  alias Botyaga.Saft.{Annual, GL, Load, Mode, Moves, Ownership, Src, Validate, Xml}
  alias Botyaga.Stock.Replay

  @ns "mf:nra:dgti:dxxxx:declaration:v1"

  def export(company_id, params) do
    period = params |> str("period") |> String.trim()

    case parse_period(period) do
      :error ->
        {:error, {400, "period е задължителен (YYYY-MM-01)"}}

      {:ok, year, month} ->
        mode = mode_of(str(params, "mode"))

        with {:ok, snap} <- Load.load(company_id),
             {:ok, range} <- range_of(mode, params) do
          xml =
            case range do
              nil -> build(snap, period, year, month, mode)
              {from, to} -> build_ranged(snap, period, company_id, from, to)
            end

          {:ok, %{xml: xml, filename: "saft_#{period}_#{mode}.xml"}}
        end
    end
  end

  @doc "Експорт плюс валидация: връща XML с errors/warnings, но не спира извеждането."
  def preview(company_id, params) do
    with {:ok, result} <- export(company_id, params),
         {:ok, snap} <- Load.load(company_id) do
      validation = Validate.validate(result.xml, snap, str(params, "mode"))
      {:ok, Map.put(result, :validation, validation)}
    end
  end

  defp range_of("ondemand", params),
    do: ondemand_range(Map.get(params, "date_from"), Map.get(params, "date_to"))

  defp range_of(_mode, _params), do: {:ok, nil}

  defp build(s, period, year, month, mode) do
    body =
      case mode do
        "annual" -> Annual.annual_xml(s, year)
        "ondemand" -> Moves.ondemand_xml(s)
        _ -> monthly(s, year, month)
      end

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<nsSAFT:AuditFile xmlns:nsSAFT=\"#{@ns}\">" <>
      header(s, period, year, month, mode, nil) <>
      body <>
      "</nsSAFT:AuditFile>"
  end

  defp monthly(s, year, month) do
    {sales, buys} = Src.invoices_xml(s, year, month)

    Xml.open("MasterFilesMonthly") <>
      GL.accounts_xml(s, year, month) <>
      Src.parties_xml(s, year, month) <>
      Mode.tax_table() <>
      Mode.uom_products(s) <>
      Xml.close("MasterFilesMonthly") <>
      GL.entries_xml(s, year, month) <>
      Xml.open("SourceDocumentsMonthly") <>
      sales <>
      Mode.payments_xml(s, year, month) <>
      buys <>
      Xml.close("SourceDocumentsMonthly")
  end

  defp ondemand_range(from, to) when is_nil(from) or is_nil(to), do: {:ok, nil}

  defp ondemand_range(from, to) do
    with {:ok, f} <- Date.from_iso8601(String.trim(from)),
         {:ok, t} <- Date.from_iso8601(String.trim(to)) do
      if Date.compare(f, t) == :gt,
        do: {:error, {400, "date_from трябва да е преди или равен на date_to"}},
        else: {:ok, {f, t}}
    else
      _ -> {:error, {400, "date_from и date_to са във формат YYYY-MM-DD"}}
    end
  end

  defp build_ranged(s, period, cid, from, to) do
    {:ok, open} = stock_map(cid, Date.add(from, -1))
    {:ok, close} = stock_map(cid, to)
    from_s = Date.to_iso8601(from)
    to_s = Date.to_iso8601(to)
    span = {from.month, from.year, to.month, to.year}

    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
      "<nsSAFT:AuditFile xmlns:nsSAFT=\"#{@ns}\">" <>
      header(s, period, to.year, to.month, "ondemand", span) <>
      Moves.ondemand_xml_ranged(s, open, close, from_s, to_s) <>
      "</nsSAFT:AuditFile>"
  end

  defp stock_map(cid, day) do
    {:ok, out} = Replay.explain(cid, Date.to_iso8601(day))

    map =
      Enum.reduce(out.balances, %{}, fn b, acc ->
        {q, v} = Map.get(acc, b.product_id, {0, 0})
        Map.put(acc, b.product_id, {q + Dec.or0(b.quantity), v + Dec.or0(b.value)})
      end)

    {:ok, Map.new(map, fn {id, {q, v}} -> {id, {Dec.text(q, 4), v}} end)}
  end

  defp header(s, period, year, month, mode, span) do
    c = s.company

    {start, start_year, end_m, end_year} =
      case span do
        nil -> if mode == "annual", do: {1, year, 12, year}, else: {month, year, month, year}
        v -> v
      end

    comment =
      case mode do
        "annual" -> "A"
        "ondemand" -> "D"
        _ -> "M"
      end

    cc = Xml.country(c.country)

    region =
      case Xml.region_code(c.region, cc) do
        nil -> ""
        code -> Xml.clip(code, 9)
      end

    region_xml = if region == "", do: "", else: Xml.text("AuditFileRegion", region)
    entity = Xml.clip(c.entity, 70)
    entity_xml = if entity == "", do: "", else: Xml.text("TaxEntity", entity)

    Xml.open("Header") <>
      Xml.text("AuditFileVersion", "007") <>
      Xml.text("AuditFileCountry", "BG") <>
      region_xml <>
      Xml.text("AuditFileDateCreated", period) <>
      Xml.text("SoftwareCompanyName", filled(c.soft_name, "botyaga", 70)) <>
      Xml.text("SoftwareID", filled(c.soft_id, "BOTYAGA", 256)) <>
      Xml.text("SoftwareVersion", filled(c.soft_ver, "1.0", 18)) <>
      company_xml(c, s.bank_accounts) <>
      Ownership.ownership(s) <>
      Xml.text("DefaultCurrencyCode", currency_code(c.currency)) <>
      Xml.open("SelectionCriteria") <>
      Xml.text("TaxReportingJurisdiction", "NRA") <>
      Xml.text("PeriodStart", Integer.to_string(start)) <>
      Xml.text("PeriodStartYear", Integer.to_string(start_year)) <>
      Xml.text("PeriodEnd", Integer.to_string(end_m)) <>
      Xml.text("PeriodEndYear", Integer.to_string(end_year)) <>
      Xml.text("DocumentType", "F") <>
      Xml.close("SelectionCriteria") <>
      Xml.text("HeaderComment", comment) <>
      Xml.text("TaxAccountingBasis", basis(c.basis)) <>
      entity_xml <>
      Xml.close("Header")
  end

  defp company_xml(c, bank_accounts) do
    eik = eik_or0(c.eik)
    {first, last} = person(c.mol)
    phone = Xml.clip(c.phone, 18)
    email = Xml.clip(c.email, 70)
    site = String.trim(c.website || "")
    vat = Xml.clip(c.vat, 35)

    bank_accounts_xml =
      bank_accounts
      |> Enum.map(fn a ->
        number =
          if a.iban != "",
            do: Xml.text("IBANNumber", Xml.clip(a.iban, 35)),
            else: Xml.text("AccountNumber", Xml.clip(a.account_number, 35))

        Xml.open("BankAccount") <> number <> Xml.close("BankAccount")
      end)
      |> Enum.join("")

    website =
      if String.starts_with?(site, "http://") or String.starts_with?(site, "https://"),
        do: Xml.text("Website", Xml.clip(site, 256)),
        else: ""

    Xml.open("Company") <>
      Xml.text("RegistrationNumber", eik) <>
      Xml.text("Name", shown(c.name)) <>
      Xml.address("Address", %{
        street: c.street,
        number: c.number,
        extra: c.extra,
        building: c.building,
        city: c.city,
        post: c.post,
        region: c.region,
        country: c.country,
        kind: c.addr_type
      }) <>
      Xml.open("Contact") <>
      Xml.open("ContactPerson") <>
      Xml.text("FirstName", first) <>
      Xml.text("LastName", last) <>
      Xml.text("OtherTitles", "МОЛ") <>
      Xml.close("ContactPerson") <>
      if(phone == "", do: "", else: Xml.text("Telephone", phone)) <>
      if(email == "", do: "", else: Xml.text("Email", email)) <>
      website <>
      Xml.close("Contact") <>
      Xml.open("TaxRegistration") <>
      Xml.text("TaxRegistrationNumber", eik) <>
      Xml.text("TaxType", "100010") <>
      if(vat == "", do: "", else: Xml.text("TaxNumber", vat)) <>
      Xml.close("TaxRegistration") <>
      bank_accounts_xml <>
      Xml.close("Company")
  end

  defp parse_period(raw) do
    with true <- String.length(raw) == 10,
         true <-
           String.slice(raw, 4, 1) == "-" and String.slice(raw, 7, 1) == "-" and
             String.slice(raw, 8, 2) == "01",
         {year, ""} <- Integer.parse(String.slice(raw, 0, 4)),
         {month, ""} <- Integer.parse(String.slice(raw, 5, 2)),
         true <- month in 1..12 do
      {:ok, year, month}
    else
      _ -> :error
    end
  end

  defp mode_of(raw) do
    case String.trim(raw || "") do
      "annual" -> "annual"
      "ondemand" -> "ondemand"
      _ -> "monthly"
    end
  end

  defp basis(raw) do
    t = String.trim(raw || "")
    if t in ["A", "P", "BANK", "INSURANCE"], do: t, else: "A"
  end

  defp currency_code(raw) do
    u = raw |> String.trim() |> String.upcase()
    if String.length(u) == 3 and String.match?(u, ~r/^[A-Z]{3}$/), do: u, else: "EUR"
  end

  defp filled(value, fallback, n) do
    t = Xml.clip(value, n)
    if t == "", do: Xml.clip(fallback, n), else: t
  end

  defp person(mol) do
    t = String.trim(mol || "")

    if t == "" do
      {"—", "—"}
    else
      parts = String.split(t, ~r/\s+/, trim: true)
      first = Xml.clip(Enum.at(parts, 0, "—"), 35)
      rest = parts |> Enum.drop(1) |> Enum.join(" ")
      last = if rest == "", do: first, else: Xml.clip(rest, 70)
      first = if first == "", do: "—", else: first
      {first, if(last == "", do: "—", else: last)}
    end
  end

  defp shown(name) do
    t = Xml.clip(name, 70)
    if t == "", do: "—", else: t
  end

  defp eik_or0(eik), do: or_clip(eik, 35, "0")

  defp or_clip(value, n, fallback) do
    c = Xml.clip(value, n)
    if c == "", do: fallback, else: c
  end

  defp str(params, key) do
    case Botyaga.Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

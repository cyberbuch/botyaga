defmodule Botyaga.Ubl do
  @moduledoc """
  UBL 2.1 / Peppol BIS Billing 3.0 експорт. Кредитното е CreditNote (381),
  проформа 325, TaxCurrencyCode при валута != EUR. Фирмата е доставчик.
  Порт на `invoice_ubl.rs`.
  """

  alias Botyaga.Dec
  alias Botyaga.Printing
  alias Botyaga.Printing.Load
  alias Botyaga.Vat

  @eu ~w(AT BE BG CY CZ DE DK EE ES FI FR GR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK)

  def build(company_id, id) do
    with {:ok, loaded} <- Load.load(company_id, id) do
      xml = document(loaded)
      kind = if is_credit(loaded.inv.document_type), do: "credit-note", else: "invoice"
      filename = "ubl-#{kind}-#{Printing.safe_name(loaded.inv.number)}.xml"
      {:ok, %{xml: xml, filename: filename}}
    end
  end

  def document(doc) do
    inv = doc.inv
    credit = is_credit(inv.document_type)
    company = Load.party(doc.company)
    customer = Load.party(doc.counterpart)

    customer =
      if customer.name == "", do: %{customer | name: inv.counterpart_name || ""}, else: customer

    currency = or_trim(inv.currency, "EUR")
    pay_iban = or_trim(Load.field(doc.bank, :iban), "")
    pay_bic = or_trim(Load.field(doc.bank, :bic), "")
    root = if credit, do: "CreditNote", else: "Invoice"

    ns =
      if credit,
        do: "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2",
        else: "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"

    out =
      ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
        ~s(<#{root} xmlns="#{ns}" ) <>
        ~s(xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" ) <>
        ~s(xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">)

    out =
      out <>
        cbc("UBLVersionID", "2.1") <>
        cbc(
          "CustomizationID",
          "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
        ) <>
        cbc("ProfileID", "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0") <>
        cbc("ID", inv.number) <>
        cbc("IssueDate", iso_day(inv.issue_date))

    out =
      if credit,
        do: out <> cbc("CreditNoteTypeCode", "381"),
        else:
          out <>
            cbc("DueDate", iso_day(inv.due_date)) <>
            cbc("InvoiceTypeCode", doc_code(inv.document_type))

    tax_cur = needs_eur(currency, inv.currency_rate)

    out =
      out <>
        cbc("Note", String.trim(inv.notes || "")) <>
        cbc("TaxPointDate", iso_day(inv.tax_event_date)) <>
        cbc("DocumentCurrencyCode", currency) <>
        if(tax_cur, do: cbc("TaxCurrencyCode", "EUR"), else: "") <>
        cbc("BuyerReference", inv.number)

    out =
      if String.trim(doc.original_number) != "" do
        out <>
          open("BillingReference") <>
          open("InvoiceDocumentReference") <>
          cbc("ID", String.trim(doc.original_number)) <>
          cbc("IssueDate", iso_day(doc.original_date)) <>
          close("InvoiceDocumentReference") <>
          close("BillingReference")
      else
        out
      end

    out =
      out <>
        open("AdditionalDocumentReference") <>
        cbc("ID", "Software") <>
        cbc("DocumentDescription", "botyaga") <>
        close("AdditionalDocumentReference")

    out =
      if tax_cur do
        out <>
          open("TaxExchangeRate") <>
          cbc("SourceCurrencyCode", currency) <>
          cbc("TargetCurrencyCode", "EUR") <>
          cbc("CalculationRate", inv_rate(inv.currency_rate)) <>
          close("TaxExchangeRate")
      else
        out
      end

    out =
      out <>
        party("AccountingSupplierParty", company) <> party("AccountingCustomerParty", customer)

    out =
      out <>
        open("PaymentMeans") <>
        cbc("PaymentMeansCode", pay_code(String.trim(inv.payment_method || "")))

    out =
      if pay_iban != "" do
        branch =
          if pay_bic != "",
            do:
              open("FinancialInstitutionBranch") <>
                cbc("ID", pay_bic) <> close("FinancialInstitutionBranch"),
            else: ""

        out <>
          open("PayeeFinancialAccount") <>
          cbc("ID", pay_iban) <> branch <> close("PayeeFinancialAccount")
      else
        out
      end

    exemption = String.trim(inv.vat_exemption_reason || "")

    out =
      out <>
        close("PaymentMeans") <>
        tax_total(doc.lines, currency, inv.vat_amount, exemption)

    out =
      if tax_cur do
        out <>
          open("TaxTotal") <>
          amt("TaxAmount", "EUR", to_eur(inv.vat_amount, inv.currency_rate)) <>
          close("TaxTotal")
      else
        out
      end

    net = Dec.money(Dec.or0(inv.net_amount))
    total = Dec.money(Dec.or0(inv.total_amount))

    out =
      out <>
        open("LegalMonetaryTotal") <>
        amt("LineExtensionAmount", currency, net) <>
        amt("TaxExclusiveAmount", currency, net) <>
        amt("TaxInclusiveAmount", currency, total) <>
        amt("PayableAmount", currency, total) <>
        close("LegalMonetaryTotal")

    out =
      out <>
        (doc.lines
         |> Enum.with_index()
         |> Enum.map_join(fn {line, i} -> line_xml(line, i, currency, credit, exemption) end))

    out <> "</#{root}>"
  end

  defp party(tag, p) do
    cc = country(p.vat, p.country)

    endpoint =
      if p.vat != "", do: cbc_attr("EndpointID", [{"schemeID", scheme(p.vat)}], p.vat), else: ""

    identification =
      if p.eik != "",
        do:
          open("PartyIdentification") <>
            cbc_attr("ID", [{"schemeID", "0195"}], p.eik) <> close("PartyIdentification"),
        else: ""

    tax_scheme =
      if p.vat != "" do
        open("PartyTaxScheme") <>
          cbc("CompanyID", p.vat) <>
          open("TaxScheme") <>
          cbc("ID", "VAT") <>
          close("TaxScheme") <>
          close("PartyTaxScheme")
      else
        ""
      end

    legal_company =
      if p.eik != "", do: cbc_attr("CompanyID", [{"schemeID", "0195"}], p.eik), else: ""

    contact =
      if p.email != "" or p.phone != "",
        do:
          open("Contact") <>
            cbc("Telephone", p.phone) <> cbc("ElectronicMail", p.email) <> close("Contact"),
        else: ""

    open(tag) <>
      open("Party") <>
      endpoint <>
      identification <>
      open("PartyName") <>
      cbc("Name", p.name) <>
      close("PartyName") <>
      open("PostalAddress") <>
      cbc("StreetName", p.address) <>
      cbc("CityName", p.city) <>
      cbc("PostalZone", p.post) <>
      open("Country") <>
      cbc("IdentificationCode", cc) <>
      close("Country") <>
      close("PostalAddress") <>
      tax_scheme <>
      open("PartyLegalEntity") <>
      cbc("RegistrationName", p.name) <>
      legal_company <>
      close("PartyLegalEntity") <>
      contact <>
      close("Party") <>
      close(tag)
  end

  defp tax_total(lines, currency, vat_total, exemption) do
    groups =
      Enum.reduce(lines, [], fn line, groups ->
        rate = String.trim(line.vat_rate || "")
        net = Dec.or0(line.net_amount)
        vat = Dec.or0(line.vat_amount)

        case Enum.find_index(groups, fn {r, _, _} -> r == rate end) do
          nil ->
            groups ++ [{rate, net, vat}]

          idx ->
            {r, n, v} = Enum.at(groups, idx)
            List.replace_at(groups, idx, {r, n + net, v + vat})
        end
      end)

    subtotals =
      Enum.map_join(groups, fn {rate, net, vat} ->
        open("TaxSubtotal") <>
          amt("TaxableAmount", currency, Dec.money(net)) <>
          amt("TaxAmount", currency, Dec.money(vat)) <>
          tax_category(rate, exemption) <>
          close("TaxSubtotal")
      end)

    open("TaxTotal") <> amt("TaxAmount", currency, vat_total) <> subtotals <> close("TaxTotal")
  end

  defp line_xml(line, index, currency, credit, exemption) do
    {tag, qty_tag} =
      if credit,
        do: {"CreditNoteLine", "CreditedQuantity"},
        else: {"InvoiceLine", "InvoicedQuantity"}

    rate = or_trim(line.vat_rate, "0")
    cat = tax_id(rate, exemption)

    open(tag) <>
      cbc("ID", Integer.to_string(index + 1)) <>
      qty_el(qty_tag, unit_code(line.unit), String.trim(line.quantity || "")) <>
      amt("LineExtensionAmount", currency, line.net_amount) <>
      open("Item") <>
      cbc("Name", String.trim(line.description || "")) <>
      open("ClassifiedTaxCategory") <>
      cbc("ID", cat) <>
      cbc("Percent", rate) <>
      open("TaxScheme") <>
      cbc("ID", "VAT") <>
      close("TaxScheme") <>
      close("ClassifiedTaxCategory") <>
      close("Item") <>
      open("Price") <>
      amt("PriceAmount", currency, line.unit_price) <>
      close("Price") <>
      close(tag)
  end

  defp tax_category(rate, exemption) do
    shown = if rate == "", do: "0", else: rate
    cat = tax_id(shown, exemption)

    reason =
      if cat != "S" and exemption != "" do
        code = Vat.Ex.ubl_reason(exemption)
        code_xml = if code != "", do: cbc("TaxExemptionReasonCode", code), else: ""
        code_xml <> cbc("TaxExemptionReason", Vat.Ex.legal_en(exemption))
      else
        ""
      end

    open("TaxCategory") <>
      cbc("ID", cat) <>
      cbc("Percent", shown) <>
      reason <>
      open("TaxScheme") <>
      cbc("ID", "VAT") <>
      close("TaxScheme") <>
      close("TaxCategory")
  end

  defp tax_id(rate, exemption) do
    cond do
      Dec.or0(rate) != 0 -> "S"
      exemption == "" -> "Z"
      true -> Vat.Ex.category(exemption)
    end
  end

  def is_credit(t), do: t in ["03", "13", "23"]

  def doc_code(t) do
    case t do
      "proforma" -> "325"
      t when t in ["02", "12"] -> "383"
      t when t in ["03", "13", "23"] -> "381"
      _ -> "380"
    end
  end

  def pay_code(method) do
    case method do
      "в брой" -> "10"
      "карта" -> "48"
      _ -> "30"
    end
  end

  def unit_code(code) do
    case String.trim(code || "") do
      u when u in ["", "бр.", "бр", "брой"] ->
        "C62"

      u when u in ["кг", "кг."] ->
        "KGM"

      u when u in ["л", "л."] ->
        "LTR"

      u when u in ["м", "м."] ->
        "MTR"

      u when u in ["час", "ч"] ->
        "HUR"

      u when u in ["ден", "дни"] ->
        "DAY"

      u when u in ["пакет", "опак."] ->
        "PK"

      other ->
        if String.length(other) <= 3 and String.match?(other, ~r/^[A-Za-z0-9]+$/),
          do: other,
          else: "C62"
    end
  end

  def country(vat, fallback) do
    v = String.trim(vat || "")

    eu_code =
      if String.length(v) >= 2 do
        p = String.slice(v, 0, 2)
        p = if p == "EL", do: "GR", else: p
        if p in @eu, do: p
      end

    f = String.trim(fallback || "")

    cond do
      eu_code != nil -> eu_code
      f == "" -> "BG"
      true -> f
    end
  end

  def scheme(vat) do
    case country(vat, "BG") do
      "DE" -> "9930"
      "AT" -> "9914"
      "FR" -> "9957"
      "IT" -> "9906"
      "NL" -> "9944"
      "PL" -> "9945"
      "PT" -> "9946"
      "RO" -> "9948"
      "ES" -> "9920"
      "SE" -> "9955"
      "SK" -> "9929"
      "SI" -> "9928"
      "GR" -> "9933"
      "HU" -> "9910"
      "CZ" -> "9932"
      "HR" -> "9934"
      "DK" -> "9917"
      c when c in ["FI", "IE"] -> "9935"
      _ -> "9947"
    end
  end

  def needs_eur(currency, rate) do
    r = String.trim(rate || "")
    currency != "" and currency != "EUR" and r != "" and r not in ["1", "1.00", "1.000000"]
  end

  defp to_eur(amount, rate) do
    a = Dec.or0(amount)
    r = Dec.or0(rate)
    Dec.money(Dec.div(a, r) || a)
  end

  defp inv_rate(rate) do
    r = Dec.or0(rate)
    one = Dec.parse("1") || 0
    if r == 0, do: "1", else: Dec.text(Dec.div(one, r) || one, 6)
  end

  defp iso_day(raw) do
    s = String.trim(raw || "")

    if String.length(s) >= 10 and String.slice(s, 4, 1) == "-",
      do: String.slice(s, 0, 10),
      else: s
  end

  defp cbc(name, text) do
    t = String.trim(text || "")
    if t == "", do: "", else: "<cbc:#{name}>#{esc(t)}</cbc:#{name}>"
  end

  defp cbc_attr(name, attrs, text) do
    t = String.trim(text || "")

    if t == "" do
      ""
    else
      a = Enum.map_join(attrs, fn {k, v} -> " #{k}=\"#{esc(v)}\"" end)
      "<cbc:#{name}#{a}>#{esc(t)}</cbc:#{name}>"
    end
  end

  defp amt(name, currency, amount) do
    "<cbc:#{name} currencyID=\"#{esc(currency)}\">#{esc(Dec.money(Dec.or0(amount)))}</cbc:#{name}>"
  end

  defp qty_el(name, unit, qty) do
    v = if qty == "", do: "0", else: qty
    "<cbc:#{name} unitCode=\"#{esc(unit)}\">#{esc(v)}</cbc:#{name}>"
  end

  defp open(name), do: "<cac:#{name}>"
  defp close(name), do: "</cac:#{name}>"
  defp esc(s), do: Printing.xml_escape(s)

  defp or_trim(value, fallback) do
    t = String.trim(value || "")
    if t == "", do: fallback, else: t
  end
end

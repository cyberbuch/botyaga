defmodule Botyaga.Saft.Src do
  @moduledoc """
  Клиенти, доставчици и фактури за месечния SAF-T. Осчетоводен ред без product_id:
  продажба взима дебит 411 и кредит извън 453, покупка — кредит 401 и дебит извън
  453. Без дневник остават 411/702 и 401/601. Порт на `saft_src.rs`.
  """

  alias Botyaga.Dec
  alias Botyaga.Saft.{GL, Xml}

  def parties_xml(s, year, month) do
    w = Xml.window(year, month, s.company.fys)
    map = GL.balances(s, w)

    {customers, suppliers} =
      Enum.reduce(s.parties, {"", ""}, fn p, {cust, supp} ->
        if not Xml.same_co(p.company_id, s.company_id) do
          {cust, supp}
        else
          {client, supplier} = GL.roles(p.kind)
          id = eik_or0(p.eik)

          cust =
            if client,
              do: cust <> party("Customer", "CustomerID", p, id, "411", side(map, p.id, "c")),
              else: cust

          supp =
            if supplier,
              do: supp <> party("Supplier", "SupplierID", p, id, "401", side(map, p.id, "s")),
              else: supp

          {cust, supp}
        end
      end)

    Xml.open("Customers") <>
      customers <>
      Xml.close("Customers") <>
      Xml.open("Suppliers") <> suppliers <> Xml.close("Suppliers")
  end

  defp party(tag, id_tag, p, id, account, sides) do
    Xml.open(tag) <>
      company(p) <>
      Xml.text(id_tag, id) <>
      Xml.text("AccountID", account) <>
      sides <>
      Xml.close(tag)
  end

  defp company(p) do
    name = Xml.clip(p.name, 70)
    reg = eik_or0(p.eik)

    name_xml =
      if Xml.cyr(name) or name == "",
        do: Xml.text("Name", Xml.shown_name(name, 70)),
        else: Xml.text("NameLatin", name)

    addr =
      Xml.address("Address", %{
        street: p.street,
        number: p.number,
        extra: p.extra,
        building: p.building,
        city: p.city,
        post: p.post,
        region: p.region,
        country: p.country,
        kind: p.addr_type
      })

    vat = Xml.clip(p.vat, 35)

    tax =
      if vat == "",
        do: "",
        else:
          Xml.open("TaxRegistration") <>
            Xml.text("TaxRegistrationNumber", reg) <>
            Xml.text("TaxType", "100010") <>
            Xml.text("TaxNumber", vat) <>
            Xml.close("TaxRegistration")

    Xml.open("CompanyStructure") <>
      Xml.text("RegistrationNumber", reg) <>
      name_xml <>
      addr <>
      tax <>
      Xml.text("RelatedParty", "N") <>
      Xml.close("CompanyStructure")
  end

  defp side(map, id, role) do
    od = GL.get(map, "p:#{id}:#{role}:od")
    oc = GL.get(map, "p:#{id}:#{role}:oc")
    pd = GL.get(map, "p:#{id}:#{role}:pd")
    pc = GL.get(map, "p:#{id}:#{role}:pc")

    Xml.bal("OpeningDebitBalance", "OpeningCreditBalance", od, oc) <>
      Xml.bal("ClosingDebitBalance", "ClosingCreditBalance", od + pd, oc + pc)
  end

  def invoices_xml(s, year, month) do
    prefix = "#{pad(year, 4)}-#{pad(month, 2)}"
    cur = GL.currency(s)

    {sales, purchases, ns, np, credit, debit} =
      Enum.reduce(s.invoices, {"", "", 0, 0, 0, 0}, fn inv, {sa, pu, ns, np, cr, de} ->
        cond do
          inv.document_type == "proforma" or not Xml.same_co(inv.company_id, s.company_id) ->
            {sa, pu, ns, np, cr, de}

          inv.direction not in ["out", "in"] ->
            {sa, pu, ns, np, cr, de}

          month_key(inv) != prefix or String.length(inv.issue_date) < 10 ->
            {sa, pu, ns, np, cr, de}

          true ->
            xml = one(s, inv, year, month, cur)

            if inv.direction == "out",
              do: {sa <> xml, pu, ns + 1, np, cr + inv.total, de},
              else: {sa, pu <> xml, ns, np + 1, cr, de + inv.total}
        end
      end)

    {wrap("SalesInvoices", ns, 0, credit, sales),
     wrap("PurchaseInvoices", np, debit, 0, purchases)}
  end

  defp wrap(_tag, _n, _debit, _credit, ""), do: ""

  defp wrap(tag, n, debit, credit, body) do
    Xml.open(tag) <>
      Xml.text("NumberOfEntries", Integer.to_string(n)) <>
      Xml.text("TotalDebit", Dec.money(debit)) <>
      Xml.text("TotalCredit", Dec.money(credit)) <>
      body <>
      Xml.close(tag)
  end

  defp one(s, inv, year, month, cur) do
    day = String.slice(inv.issue_date, 0, 10)

    tax_day =
      if String.length(inv.tax_date) >= 10, do: String.slice(inv.tax_date, 0, 10), else: day

    icur = or_trim(inv.currency, cur)
    purchase = inv.direction == "in"
    {header0, line_acc0} = if purchase, do: {"401", "601"}, else: {"411", "702"}

    {header, line_acc} =
      if inv.journal_entry_id > 0 do
        case Map.get(s.lines, inv.journal_entry_id) do
          nil ->
            {header0, line_acc0}

          lines ->
            {h, l} = journal_accounts(s, lines, purchase)
            {if(h == "", do: header0, else: h), if(l == "", do: line_acc0, else: l)}
        end
      else
        {header0, line_acc0}
      end

    party = Enum.find(s.parties, &(&1.id == inv.counterpart_id))
    eik = (party && party.eik) || ""
    name = (party && party.name) || ""
    city = (party && party.city) || ""
    country = (party && party.country) || "BG"
    lines = Map.get(s.inv_lines, inv.id, [])
    indicator = if purchase, do: "D", else: "C"

    body =
      if lines == [] do
        line_xml(%{
          number: "1",
          account: line_acc,
          goods: "01",
          code: "0",
          desc: "Фактура",
          qty: "1",
          unit: "C62",
          price: inv.net,
          net: inv.net,
          vat: inv.vat,
          rate: 20 * Dec.scale(),
          reason: inv.reason,
          day: tax_day,
          indicator: indicator,
          currency: icur
        })
      else
        lines
        |> Enum.with_index()
        |> Enum.map_join(fn {row, i} ->
          prod = product_of(s, row)
          code = prod_code(prod)
          goods = if prod && prod.service, do: "02", else: "01"
          unit = or_clip(row.unit, 9, "C62")
          qty = or_trim(row.quantity, "1")

          line_xml(%{
            number: Integer.to_string(i + 1),
            account: line_acc,
            goods: goods,
            code: code,
            desc: row.description,
            qty: qty,
            unit: unit,
            price: row.price,
            net: row.net,
            vat: row.vat,
            rate: row.rate,
            reason: inv.reason,
            day: tax_day,
            indicator: indicator,
            currency: icur
          })
        end)
      end

    dtype =
      if String.length(inv.document_type) == 2 and
           String.match?(inv.document_type, ~r/^[0-9]{2}$/),
         do: inv.document_type,
         else: "01"

    txn = if inv.journal_entry_id > 0, do: inv.journal_entry_id, else: inv.id

    Xml.open("Invoice") <>
      Xml.text("InvoiceNo", Xml.clip(inv.number, 70)) <>
      info(purchase, eik, name, city, country) <>
      Xml.text("AccountID", header) <>
      Xml.text("Period", Integer.to_string(month)) <>
      Xml.text("PeriodYear", Integer.to_string(year)) <>
      Xml.text("InvoiceDate", day) <>
      Xml.text("InvoiceType", dtype) <>
      Xml.text("SelfBillingIndicator", "N") <>
      Xml.text("TransactionID", Integer.to_string(txn)) <>
      body <>
      Xml.open("InvoiceDocumentTotals") <>
      Xml.text("NetTotal", Dec.money(inv.net)) <>
      Xml.text("GrossTotal", Dec.money(inv.total)) <>
      Xml.close("InvoiceDocumentTotals") <>
      Xml.close("Invoice")
  end

  defp journal_accounts(s, lines, purchase) do
    want_h = if purchase, do: "credit", else: "debit"
    want_l = if purchase, do: "debit", else: "credit"
    prefix = if purchase, do: "401", else: "411"

    Enum.reduce(lines, {"", ""}, fn row, {header, line} ->
      case Map.get(s.nra, row.account_id) do
        nil ->
          {header, line}

        code ->
          header = if row.direction == want_h and Xml.pref(code, prefix), do: code, else: header

          line =
            if row.direction == want_l and not String.starts_with?(code, "453") and row.vat == 0,
              do: code,
              else: line

          {header, line}
      end
    end)
  end

  defp product_of(s, line) do
    by_id =
      if line.product_id > 0,
        do:
          Enum.find(
            s.products,
            &(&1.id == line.product_id and Xml.same_co(&1.company_id, s.company_id))
          )

    if by_id do
      by_id
    else
      code = String.trim(line.code || "")

      if code == "",
        do: nil,
        else:
          Enum.find(
            s.products,
            &(String.trim(&1.code || "") == code and Xml.same_co(&1.company_id, s.company_id))
          )
    end
  end

  defp prod_code(nil), do: "0"

  defp prod_code(p) do
    c = Xml.clip(p.code, 70)
    if c == "", do: "0", else: c
  end

  defp info(purchase, eik, name, city, country) do
    {tag, id_tag} =
      if purchase, do: {"SupplierInfo", "SupplierID"}, else: {"CustomerInfo", "CustomerID"}

    Xml.open(tag) <>
      Xml.text(id_tag, eik_or0(eik)) <>
      Xml.text("Name", Xml.shown_name(name, 70)) <>
      Xml.open("BillingAddress") <>
      Xml.text("City", Xml.clip(city, 35)) <>
      Xml.text("Country", Xml.country(country)) <>
      Xml.close("BillingAddress") <>
      Xml.close(tag)
  end

  defp line_xml(m) do
    text_d = or_clip(m.desc, 256, "Ред")

    Xml.open("InvoiceLine") <>
      Xml.text("LineNumber", m.number) <>
      Xml.text("AccountID", m.account) <>
      Xml.text("GoodsServicesID", m.goods) <>
      Xml.text("ProductCode", Xml.clip(m.code, 70)) <>
      Xml.text("ProductDescription", text_d) <>
      Xml.text("Quantity", m.qty) <>
      Xml.text("InvoiceUOM", m.unit) <>
      Xml.text("UnitPrice", Dec.money(m.price)) <>
      Xml.text("TaxPointDate", m.day) <>
      Xml.text("Description", text_d) <>
      Xml.amount("InvoiceLineAmount", m.net, m.currency) <>
      Xml.text("DebitCreditIndicator", m.indicator) <>
      Xml.open("TaxInformation") <>
      Xml.text("TaxType", "100") <>
      Xml.text("TaxCode", tax_code(m.rate, m.vat, m.reason)) <>
      Xml.text("TaxBase", Dec.money(m.net)) <>
      Xml.amount("TaxAmount", m.vat, m.currency) <>
      Xml.close("TaxInformation") <>
      Xml.close("InvoiceLine")
  end

  defp tax_code(rate, vat, reason) do
    s = Dec.scale()

    cond do
      rate == 20 * s -> "100211"
      rate == 9 * s -> "100213"
      vat == 0 and String.trim(reason || "") != "" -> "100219"
      rate == 0 -> "100214"
      true -> "100211"
    end
  end

  defp month_key(inv) do
    if String.length(inv.accounting_month) >= 7,
      do: String.slice(inv.accounting_month, 0, 7),
      else: String.slice(inv.issue_date, 0, 7)
  end

  defp eik_or0(eik) do
    t = Xml.clip(eik, 35)
    if t == "", do: "0", else: t
  end

  defp or_clip(value, n, fallback) do
    c = Xml.clip(value, n)
    if c == "", do: fallback, else: c
  end

  defp or_trim(value, fallback) do
    c = String.trim(value || "")
    if c == "", do: fallback, else: c
  end

  defp pad(v, n), do: v |> Integer.to_string() |> String.pad_leading(n, "0")
end

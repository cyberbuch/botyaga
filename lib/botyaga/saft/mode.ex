defmodule Botyaga.Saft.Mode do
  @moduledoc """
  Данъчна таблица, плащания и продукти за SAF-T. Месец без осчетоводено банково
  движение пак пише Payments с нула записа (схемата иска поне един Payment).
  Порт на `saft_mode.rs` (без движенията — те са в `Saft.Moves`).
  """

  alias Botyaga.Dec
  alias Botyaga.Saft.{GL, Xml}

  def tax_table do
    Xml.open("TaxTable") <>
      tax_entry("100", "ДАНЪК ВЪРХУ ДОБАВЕНАТА СТОЙНОСТ", [
        {"100211", "20.00", "Данъчна основа на облагаемите доставки със ставка 20 %"},
        {"100213", "9.00", "ДО на облагаемите доставки със ставка 9 %"},
        {"100214", "0.00", "ДО на доставките със ставка 0 % по глава трета от ЗДДС"},
        {"100219", "0.00", "ДО на освободени доставки и освободените ВОП"}
      ]) <>
      tax_entry("000", "Неприложимо", [{"000000", "0.00", "Неприложим код"}]) <>
      Xml.close("TaxTable")
  end

  defp tax_entry(kind, desc, codes) do
    body =
      Enum.map_join(codes, fn {code, rate, name} ->
        Xml.open("TaxCodeDetails") <>
          Xml.text("TaxCode", code) <>
          Xml.text("Description", name) <>
          Xml.text("TaxPercentage", rate) <>
          Xml.text("Country", "BG") <>
          Xml.close("TaxCodeDetails")
      end)

    Xml.open("TaxTableEntry") <>
      Xml.text("TaxType", kind) <>
      Xml.text("Description", desc) <>
      body <>
      Xml.close("TaxTableEntry")
  end

  def payments_xml(s, year, month) do
    prefix = "#{pad(year, 4)}-#{pad(month, 2)}"
    cur = GL.currency(s)

    {body, n, debit, credit} =
      Enum.reduce(s.banks, {"", 0, 0, 0}, fn tx, {body, n, debit, credit} ->
        cond do
          not tx.booked or not Xml.same_co(tx.company_id, s.company_id) or
              not String.starts_with?(tx.date, prefix) ->
            {body, n, debit, credit}

          tx.gl == "" or tx.amount == 0 or String.length(tx.date) < 10 ->
            {body, n, debit, credit}

          true ->
            neg = tx.amount < 0
            mag = Kernel.abs(tx.amount)
            ind0 = if tx.kind == "WITHDRAWAL", do: "C", else: "D"
            ind = if neg, do: flip(ind0), else: ind0

            {debit, credit} =
              if ind == "D", do: {debit + mag, credit}, else: {debit, credit + mag}

            party = party_eik(s, tx.name)
            {customer, supplier} = if ind == "D", do: {party, "0"}, else: {"0", party}
            refno = or_clip(tx.reference, 35, "PAY-#{tx.id}")
            txn = if tx.journal_id > 0, do: tx.journal_id, else: tx.id
            desc = or_clip(tx.description, 256, "Плащане по банка")
            icur = or_trim(tx.currency, cur)
            day = String.slice(tx.date, 0, 10)

            xml =
              payment(%{
                refno: refno,
                month: month,
                year: year,
                txn: txn,
                date: day,
                desc: desc,
                account: tx.gl,
                customer: customer,
                supplier: supplier,
                indicator: ind,
                amount: mag,
                currency: icur,
                source: Xml.clip(tx.reference, 35)
              })

            {body <> xml, n + 1, debit, credit}
        end
      end)

    if body == "" do
      ""
    else
      Xml.open("Payments") <>
        Xml.text("NumberOfEntries", Integer.to_string(n)) <>
        Xml.text("TotalDebit", Dec.money(debit)) <>
        Xml.text("TotalCredit", Dec.money(credit)) <>
        body <>
        Xml.close("Payments")
    end
  end

  defp flip("D"), do: "C"
  defp flip(_), do: "D"

  defp payment(m) do
    Xml.open("Payment") <>
      Xml.text("PaymentRefNo", m.refno) <>
      Xml.text("Period", Integer.to_string(m.month)) <>
      Xml.text("PeriodYear", Integer.to_string(m.year)) <>
      Xml.text("TransactionID", Integer.to_string(m.txn)) <>
      Xml.text("TransactionDate", m.date) <>
      Xml.text("PaymentMethod", "03") <>
      Xml.text("Description", m.desc) <>
      Xml.text("SystemID", m.refno) <>
      Xml.text("SourceID", "ytbuch") <>
      Xml.open("PaymentLine") <>
      Xml.text("LineNumber", "1") <>
      Xml.opt("SourceDocumentID", m.source) <>
      Xml.text("AccountID", m.account) <>
      Xml.text("CustomerID", m.customer) <>
      Xml.text("SupplierID", m.supplier) <>
      Xml.text("TaxPointDate", m.date) <>
      Xml.text("Description", m.desc) <>
      Xml.text("DebitCreditIndicator", m.indicator) <>
      Xml.amount("PaymentLineAmount", m.amount, m.currency) <>
      Xml.close("PaymentLine") <>
      Xml.open("PaymentSettlement") <>
      Xml.amount("SettlementAmount", m.amount, m.currency) <>
      Xml.text("SettlementDate", m.date) <>
      Xml.text("PaymentMechanism", "42") <>
      Xml.close("PaymentSettlement") <>
      Xml.open("PaymentDocumentTotals") <>
      Xml.text("NetTotal", Dec.money(m.amount)) <>
      Xml.text("GrossTotal", Dec.money(m.amount)) <>
      Xml.close("PaymentDocumentTotals") <>
      Xml.close("Payment")
  end

  defp party_eik(s, name) do
    want = String.trim(name || "")

    if want == "" do
      "0"
    else
      Enum.find_value(s.parties, "0", fn p ->
        if String.trim(p.name || "") == want do
          eik = Xml.clip(p.eik, 35)
          if eik != "", do: eik
        end
      end)
    end
  end

  def uom_products(s) do
    products = firm_products(s)
    units = products |> Enum.map(&unit_code(&1.unit)) |> Enum.uniq()
    units = if units == [], do: ["C62"], else: units

    uom =
      Enum.map_join(units, fn u ->
        Xml.open("UOMTableEntry") <>
          Xml.text("UnitOfMeasure", u) <>
          Xml.text("Description", Xml.unit_name(u)) <>
          Xml.close("UOMTableEntry")
      end)

    prods = Enum.map_join(products, &product/1)

    Xml.open("UOMTable") <>
      uom <>
      Xml.close("UOMTable") <>
      Xml.open("Products") <> prods <> Xml.close("Products")
  end

  defp product(p) do
    code = or_clip(p.code, 70, "0")
    name = or_clip(p.name, 256, code)
    u = unit_code(p.unit)

    Xml.open("Product") <>
      Xml.text("ProductCode", code) <>
      Xml.text("GoodsServicesID", if(p.service, do: "02", else: "01")) <>
      Xml.text("Description", name) <>
      Xml.text("ProductCommodityCode", Xml.cn8_code(p.cn8_code, p.service)) <>
      Xml.text("UOMBase", u) <>
      Xml.text("UOMStandard", u) <>
      Xml.text("UOMToUOMBaseConversionFactor", "1") <>
      Xml.close("Product")
  end

  def moves do
    body =
      Enum.map_join(Xml.stock_moves(), fn {code, name} ->
        Xml.open("MovementTypeTableEntry") <>
          Xml.text("MovementType", code) <>
          Xml.text("Description", name) <>
          Xml.close("MovementTypeTableEntry")
      end)

    Xml.open("MovementTypeTable") <> body <> Xml.close("MovementTypeTable")
  end

  def firm_products(s), do: Enum.filter(s.products, &Xml.same_co(&1.company_id, s.company_id))

  def unit_code(unit) do
    u = Xml.clip(unit, 9)
    if u == "", do: "C62", else: u
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

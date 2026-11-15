defmodule Botyaga.Ubl.ParserTest do
  use ExUnit.Case, async: true

  alias Botyaga.Ubl.Parser

  @invoice """
  <?xml version="1.0" encoding="UTF-8"?>
  <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
           xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
           xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
    <cbc:ID>INV-1</cbc:ID>
    <cbc:IssueDate>2026-01-15</cbc:IssueDate>
    <cbc:DueDate>2026-02-15</cbc:DueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cac:AccountingSupplierParty><cac:Party>
      <cac:PartyName><cbc:Name>Доставчик</cbc:Name></cac:PartyName>
      <cac:PartyTaxScheme><cbc:CompanyID>BG111222333</cbc:CompanyID></cac:PartyTaxScheme>
      <cac:PartyLegalEntity><cbc:RegistrationName>Доставчик</cbc:RegistrationName><cbc:CompanyID>111222333</cbc:CompanyID></cac:PartyLegalEntity>
      <cac:PostalAddress><cac:Country><cbc:IdentificationCode>BG</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
    </cac:Party></cac:AccountingSupplierParty>
    <cac:AccountingCustomerParty><cac:Party>
      <cac:PartyName><cbc:Name>Клиент</cbc:Name></cac:PartyName>
    </cac:Party></cac:AccountingCustomerParty>
    <cac:TaxTotal><cbc:TaxAmount>20.00</cbc:TaxAmount></cac:TaxTotal>
    <cac:LegalMonetaryTotal>
      <cbc:LineExtensionAmount>100.00</cbc:LineExtensionAmount>
      <cbc:PayableAmount>120.00</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    <cac:InvoiceLine>
      <cbc:ID>1</cbc:ID>
      <cbc:InvoicedQuantity unitCode="C62">2</cbc:InvoicedQuantity>
      <cbc:LineExtensionAmount>100.00</cbc:LineExtensionAmount>
      <cac:Item><cbc:Name>Стока</cbc:Name>
        <cac:ClassifiedTaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>20</cbc:Percent></cac:ClassifiedTaxCategory>
      </cac:Item>
      <cac:Price><cbc:PriceAmount>50.00</cbc:PriceAmount></cac:Price>
    </cac:InvoiceLine>
  </Invoice>
  """

  test "parses invoice fields, parties and lines" do
    assert {:ok, d} = Parser.parse(@invoice)
    assert d.root == "Invoice"
    assert d.number == "INV-1"
    assert d.issue_date == "2026-01-15"
    assert d.due_date == "2026-02-15"
    assert d.currency == "EUR"
    assert d.net == "100.00"
    assert d.vat == "20.00"
    assert d.total == "120.00"
    assert d.supplier.name == "Доставчик"
    assert d.supplier.vat == "BG111222333"
    assert d.supplier.eik == "111222333"
    assert d.supplier.country == "BG"
    assert d.customer.name == "Клиент"
    assert length(d.lines) == 1
    line = hd(d.lines)
    assert line.name == "Стока"
    assert line.qty == "2"
    assert line.unit == "C62"
    assert line.net == "100.00"
    assert line.price == "50.00"
    assert line.pct == "20"
  end

  test "rejects non-xml and non-ubl" do
    assert {:error, "Файлът не е XML."} = Parser.parse("няма xml")
    assert {:error, "Файлът не е UBL фактура."} = Parser.parse("<Other><a>1</a></Other>")
  end

  test "document type and pay method" do
    assert Parser.document_type("CreditNote", "") == "03"
    assert Parser.document_type("Invoice", "381") == "03"
    assert Parser.document_type("Invoice", "325") == "proforma"
    assert Parser.document_type("DebitNote", "") == "02"
    assert Parser.document_type("Invoice", "380") == "01"
    assert Parser.pay_method("10") == "в брой"
    assert Parser.pay_method("48") == "карта"
    assert Parser.pay_method("30") == "банков превод"
  end

  test "exemption from category" do
    assert Parser.exemption("", "AE") == "VATEX-EU-AE"
    assert Parser.exemption("", "K") == "VATEX-EU-IC"
    assert Parser.exemption("VATEX-EU-O", "") == "VATEX-EU-O"
    assert Parser.exemption("", "S") == ""
  end
end

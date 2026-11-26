defmodule Botyaga.SaftValidateTest do
  use ExUnit.Case, async: true

  alias Botyaga.Saft.Validate

  @ok """
  <?xml version="1.0" encoding="UTF-8"?>
  <nsSAFT:AuditFile xmlns:nsSAFT="mf:nra:dgti:dxxxx:declaration:v1">
    <nsSAFT:Header>
      <nsSAFT:AuditFileVersion>007</nsSAFT:AuditFileVersion>
      <nsSAFT:AuditFileCountry>BG</nsSAFT:AuditFileCountry>
      <nsSAFT:AuditFileDateCreated>2026-11-01</nsSAFT:AuditFileDateCreated>
      <nsSAFT:SoftwareCompanyName>b</nsSAFT:SoftwareCompanyName>
      <nsSAFT:SoftwareID>B</nsSAFT:SoftwareID>
      <nsSAFT:DefaultCurrencyCode>BGN</nsSAFT:DefaultCurrencyCode>
    </nsSAFT:Header>
    <nsSAFT:MasterFilesMonthly>
      <nsSAFT:GeneralLedgerAccounts><nsSAFT:Account><nsSAFT:AccountID>411</nsSAFT:AccountID></nsSAFT:Account></nsSAFT:GeneralLedgerAccounts>
    </nsSAFT:MasterFilesMonthly>
    <nsSAFT:GeneralLedgerEntries>
      <nsSAFT:NumberOfEntries>1</nsSAFT:NumberOfEntries>
      <nsSAFT:TotalDebit>10.00</nsSAFT:TotalDebit>
      <nsSAFT:TotalCredit>10.00</nsSAFT:TotalCredit>
      <nsSAFT:Journal><nsSAFT:Transaction/></nsSAFT:Journal>
    </nsSAFT:GeneralLedgerEntries>
    <nsSAFT:SourceDocumentsMonthly>
      <nsSAFT:SalesInvoices><nsSAFT:NumberOfEntries>1</nsSAFT:NumberOfEntries><nsSAFT:Invoice/></nsSAFT:SalesInvoices>
      <nsSAFT:Payments><nsSAFT:NumberOfEntries>1</nsSAFT:NumberOfEntries><nsSAFT:Payment/></nsSAFT:Payments>
      <nsSAFT:PurchaseInvoices><nsSAFT:NumberOfEntries>1</nsSAFT:NumberOfEntries><nsSAFT:Invoice/></nsSAFT:PurchaseInvoices>
    </nsSAFT:SourceDocumentsMonthly>
  </nsSAFT:AuditFile>
  """

  test "валиден месечен файл" do
    v = Validate.validate(@ok, nil, "monthly")
    assert v.valid
    assert v.errors == []
    assert v.counts.transactions == 1
    assert v.counts.sales_invoices == 1
  end

  test "празните секции са грешки" do
    xml = String.replace(@ok, ~r/<nsSAFT:Invoice\/>/, "")
    xml = String.replace(xml, ~r/<nsSAFT:Payment\/>/, "")
    v = Validate.validate(xml, nil, "monthly")

    refute v.valid
    codes = Enum.map(v.errors, & &1.code)
    assert "source.SalesInvoices.empty" in codes
    assert "source.Payments.empty" in codes
    assert "source.PurchaseInvoices.empty" in codes
  end

  test "несъвпадащ NumberOfEntries и несбалансиран GL" do
    xml =
      String.replace(@ok, ">1</nsSAFT:NumberOfEntries>", ">5</nsSAFT:NumberOfEntries>",
        global: false
      )

    xml = String.replace(xml, "<nsSAFT:TotalCredit>10.00", "<nsSAFT:TotalCredit>99.00")
    v = Validate.validate(xml, nil, "monthly")

    assert "ledger.count" in Enum.map(v.errors, & &1.code)
    assert "ledger.balance" in Enum.map(v.errors, & &1.code)
  end

  test "грешна подредба на секциите" do
    xml =
      @ok
      |> String.replace(
        "<nsSAFT:Payments><nsSAFT:NumberOfEntries>1</nsSAFT:NumberOfEntries><nsSAFT:Payment/></nsSAFT:Payments>",
        ""
      )
      |> String.replace(
        "</nsSAFT:SourceDocumentsMonthly>",
        "<nsSAFT:Payments/></nsSAFT:SourceDocumentsMonthly>"
      )

    v = Validate.validate(xml, nil, "monthly")

    # Payments липсва като дълбока структура, но етикетът съществува — липсва NumberOfEntries
    refute v.valid
    assert "source.Payments.count" in Enum.map(v.errors, & &1.code)
  end

  test "при поискване: MovementOfGoods е задължителна" do
    xml = """
    <nsSAFT:AuditFile xmlns:nsSAFT="x"><nsSAFT:Header><nsSAFT:AuditFileVersion>007</nsSAFT:AuditFileVersion><nsSAFT:AuditFileCountry>BG</nsSAFT:AuditFileCountry><nsSAFT:AuditFileDateCreated>2026-11-01</nsSAFT:AuditFileDateCreated><nsSAFT:SoftwareCompanyName>b</nsSAFT:SoftwareCompanyName><nsSAFT:SoftwareID>B</nsSAFT:SoftwareID><nsSAFT:DefaultCurrencyCode>BGN</nsSAFT:DefaultCurrencyCode></nsSAFT:Header><nsSAFT:MasterFilesOnDemand></nsSAFT:MasterFilesOnDemand><nsSAFT:SourceDocumentsOnDemand><nsSAFT:MovementOfGoods><nsSAFT:StockMovement/></nsSAFT:MovementOfGoods></nsSAFT:SourceDocumentsOnDemand></nsSAFT:AuditFile>
    """

    assert Validate.validate(xml, nil, "ondemand").valid

    empty = String.replace(xml, "<nsSAFT:StockMovement/>", "")
    refute Validate.validate(empty, nil, "ondemand").valid
  end
end

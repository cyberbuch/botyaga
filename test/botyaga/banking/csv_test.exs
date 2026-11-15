defmodule Botyaga.Banking.CsvTest do
  use ExUnit.Case, async: true

  alias Botyaga.Banking.Csv

  test "PostBank и UniCredit XML" do
    pb = """
    <?xml version="1.0" encoding="utf-8"?>
    <AccountTransactionsHistory>
      <AccountTransactionsHistoryModel>
        <TransactionAmount><Value>500.0</Value><Currency>BGN</Currency></TransactionAmount>
        <AmountLocalCurrency><Value>255.65</Value><Currency>EUR</Currency></AmountLocalCurrency>
        <BorderNumber>1767964</BorderNumber>
        <FlowDirection>Outbound</FlowDirection>
        <TransactionType>Вътрешно банков превод</TransactionType>
        <CorrespondentAccount>BG74BPBI79404068675201</CorrespondentAccount>
        <CorrespondentName>ДИМИТЪР СОЛУНКИН</CorrespondentName>
        <RemittanceInformation>Zaplata</RemittanceInformation>
        <BookingDate>2025-12-29T00:00:00</BookingDate>
        <AccountNumber>BG93BPBI79401071567501</AccountNumber>
      </AccountTransactionsHistoryModel>
    </AccountTransactionsHistory>
    """

    p = Csv.detect(pb)
    assert p.format_name == "PostBank XML"
    assert p.account_iban == "BG93BPBI79401071567501"
    assert length(p.txs) == 1
    assert hd(p.txs).amount == "-255.65"
    assert hd(p.txs).currency == "EUR"
    assert hd(p.txs).reference == "1767964"

    uc = """
    <Items><AccountMovement>
      <Account><CCY>EUR</CCY><IBAN>BG43UNCR70001525183064</IBAN></Account>
      <Amount>1600</Amount><CCY>BGN</CCY><MovementType>Credit</MovementType>
      <OppositeSideAccount>BG23UBBS81551011107543</OppositeSideAccount>
      <OppositeSideName>СМАРТ ПРОФИЛ ООД</OppositeSideName>
      <PaymentDate>2025-09-30T00:00:00</PaymentDate>
      <Reason>Превод</Reason><DocumentReference>REF123</DocumentReference>
      <NarrativeI02>Ф-РА 13</NarrativeI02>
    </AccountMovement></Items>
    """

    u = Csv.detect(uc)
    assert u.format_name == "UniCredit XML"
    assert u.account_iban == "BG43UNCR70001525183064"
    assert length(u.txs) == 1
    assert hd(u.txs).amount == "1600.00"
    assert hd(u.txs).contra_name == "СМАРТ ПРОФИЛ ООД"
    assert hd(u.txs).reference == "REF123"
  end

  test "OBB и camt.053 XML" do
    obb = """
    <STATEMENT><IBAN_S>BG11UBBS88881010101010</IBAN_S>
      <TRANSACTION><POST_DATE>15/01/2026</POST_DATE><AMOUNT_D>120.50</AMOUNT_D>
      <NAME_R>ТЕСТ ООД</NAME_R><IBAN_R>BG22UNCR70001511111111</IBAN_R>
      <REM_I>Фактура 5</REM_I><REFERENCE>OBB-1</REFERENCE></TRANSACTION></STATEMENT>
    """

    o = Csv.detect(obb)
    assert o.format_name == "OBB XML"
    assert o.account_iban == "BG11UBBS88881010101010"
    assert length(o.txs) == 1
    assert hd(o.txs).date == "2026-01-15"
    assert hd(o.txs).amount == "-120.50"

    camt = """
    <Document><BkToCstmrStmt><Stmt>
      <Acct><Id><IBAN>BG99BNBG96611020345678</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Ntry><Amt Ccy="EUR">350.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
      <BookgDt><Dt>2026-02-10</Dt></BookgDt><AcctSvcrRef>CAMT-9</AcctSvcrRef>
      <NtryDtls><TxDtls><RltdPties><Dbtr><Nm>КЛИЕНТ АД</Nm></Dbtr>
      <DbtrAcct><Id><IBAN>BG00TEST1234</IBAN></Id></DbtrAcct></RltdPties>
      <RmtInf><Ustrd>Плащане по ф-ра 99</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
    </Stmt></BkToCstmrStmt></Document>
    """

    c = Csv.detect(camt)
    assert c.format_name == "ISO camt.053"
    assert c.account_iban == "BG99BNBG96611020345678"
    assert length(c.txs) == 1
    assert hd(c.txs).amount == "350.00"
    assert hd(c.txs).contra_name == "КЛИЕНТ АД"
    assert hd(c.txs).reference == "CAMT-9"
  end

  test "CSV с разделител и колони" do
    csv = """
    IBAN: BG93BPBI79401071567501
    Валута: EUR
    Дата;Описание;Дебит;Кредит;Референция
    2026-01-15;Плащане;120.50;;REF-1
    2026-01-16;Постъпление;;300.00;REF-2
    """

    p = Csv.detect(csv)
    assert p.format_name == "CSV"
    assert p.account_iban == "BG93BPBI79401071567501"
    assert length(p.txs) == 2
    assert Enum.at(p.txs, 0).amount == "-120.50"
    assert Enum.at(p.txs, 1).amount == "300.00"
  end

  test "MT940" do
    mt = """
    :20:START
    :25:BG93BPBI79401071567501
    :60F:C260101EUR1000,00
    :61:2601150115D120,50NTRFREF-1
    :86:Плащане към доставчик
    :61:2601160116C300,00NTRFREF-2
    :62F:C260131EUR1179,50
    """

    p = Csv.detect(mt)
    assert p.format_name == "MT940"
    assert p.account_iban == "BG93BPBI79401071567501"
    assert length(p.txs) == 2
    assert Enum.at(p.txs, 0).amount == "-120.50"
    assert Enum.at(p.txs, 0).description == "Плащане към доставчик"
    assert Enum.at(p.txs, 1).amount == "300.00"
  end

  test "непознат формат" do
    assert Csv.detect("някакъв текст без формат") == nil
  end
end

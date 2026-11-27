defmodule BotyagaWeb.UblTest do
  use BotyagaWeb.ConnCase, async: false

  alias Botyaga.{Accounts, Companies}

  @ubl """
  <?xml version="1.0" encoding="UTF-8"?>
  <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
           xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
           xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
    <cbc:ID>INV-1</cbc:ID>
    <cbc:IssueDate>2026-01-15</cbc:IssueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cac:AccountingSupplierParty><cac:Party>
      <cac:PartyName><cbc:Name>Доставчик</cbc:Name></cac:PartyName>
      <cac:PartyTaxScheme><cbc:CompanyID>BG111222333</cbc:CompanyID></cac:PartyTaxScheme>
      <cac:PartyLegalEntity><cbc:RegistrationName>Доставчик</cbc:RegistrationName><cbc:CompanyID>111222333</cbc:CompanyID></cac:PartyLegalEntity>
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
      <cbc:InvoicedQuantity unitCode="C62">2</cbc:InvoicedQuantity>
      <cbc:LineExtensionAmount>100.00</cbc:LineExtensionAmount>
      <cac:Item><cbc:Name>Стока</cbc:Name></cac:Item>
      <cac:Price><cbc:PriceAmount>50.00</cbc:PriceAmount></cac:Price>
    </cac:InvoiceLine>
  </Invoice>
  """

  setup do
    {:ok, user} =
      Accounts.create_user("ubl@baga.example", "UBL", "парола-123", "super_admin",
        is_super_admin: 1
      )

    {:ok, company, _seeded} =
      Companies.create(
        %{
          "name" => "UBL ООД",
          "eik" => "207123456",
          "vat_number" => "BG207123456",
          "is_vat_registered" => true
        },
        user
      )

    Companies.set_active(user.username, company.id)
    conn = auth_conn(build_conn(), user)
    accounts = json_response(get(conn, "/v1/accounts?limit=500"), 200)["items"]
    by_number = Map.new(accounts, &{&1["number"], &1["id"]})

    cp =
      json_response(
        post(conn, "/v1/counterparts", %{"name" => "Доставчик", "eik" => "111222333"}),
        201
      )

    goods =
      json_response(
        post(conn, "/v1/products", %{
          "name" => "Стока",
          "product_type" => "30",
          "is_inventory" => true,
          "inventory_account_id" => by_number["304"],
          "revenue_account_id" => by_number["702"]
        }),
        201
      )

    inv =
      json_response(
        post(conn, "/v1/invoices", %{
          "direction" => "out",
          "number" => "S-1",
          "issue_date" => "2026-01-15",
          "counterpart_id" => cp["id"],
          "lines" => [
            %{
              "product_id" => goods["id"],
              "description" => "Продажба",
              "quantity" => "2",
              "unit_price" => "100.00",
              "vat_rate" => "20",
              "net_amount" => "200.00",
              "vat_amount" => "40.00",
              "total_amount" => "240.00"
            }
          ]
        }),
        201
      )

    post(conn, "/v1/invoices/#{inv["id"]}/post", %{})

    {:ok, conn: conn, company: company, cp: cp, goods: goods, inv: inv}
  end

  describe "UBL експорт" do
    test "фактура 380", %{conn: conn, inv: inv} do
      conn = get(conn, "/v1/invoices/#{inv["id"]}/ubl")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
      xml = response(conn, 200)
      assert xml =~ "<Invoice"
      assert xml =~ "InvoiceTypeCode>380"
      assert xml =~ "AccountingSupplierParty"
      assert xml =~ "S-1"
      {_doc, _} = :xmerl_scan.file(String.to_charlist(write_tmp(xml)), quiet: true)
    end

    test "кредитно известие 381", %{conn: conn, cp: cp, goods: goods, inv: inv} do
      cn =
        json_response(
          post(conn, "/v1/invoices", %{
            "direction" => "out",
            "document_type" => "03",
            "number" => "CN-1",
            "issue_date" => "2026-01-20",
            "counterpart_id" => cp["id"],
            "original_invoice_id" => inv["id"],
            "lines" => [
              %{
                "product_id" => goods["id"],
                "description" => "Връщане",
                "quantity" => "1",
                "unit_price" => "100.00",
                "vat_rate" => "20",
                "net_amount" => "100.00",
                "vat_amount" => "20.00",
                "total_amount" => "120.00"
              }
            ]
          }),
          201
        )

      conn = get(conn, "/v1/invoices/#{cn["id"]}/ubl")
      xml = response(conn, 200)
      assert xml =~ "<CreditNote"
      assert xml =~ "CreditNoteTypeCode>381"
      assert xml =~ "CreditNoteLine"
    end
  end

  describe "UBL вход" do
    test "превю на чернова", %{conn: conn, cp: cp} do
      body = json_response(post(conn, "/v1/scans/ubl", %{"xml" => @ubl}), 200)
      assert body["invoice_number"] == "INV-1"
      assert body["direction"] == "in"
      assert body["document_type"] == "01"
      assert body["counterpart_name"] == "Доставчик"
      assert body["counterpart_id"] == cp["id"]
      assert body["total_amount"] == "120.00"
      assert body["total_vat_amount"] == "20.00"
      assert length(body["lines"]) == 1
      assert hd(body["lines"])["description"] == "Стока"
    end

    test "редът запазва оригиналната сума при закръглена цена", %{conn: conn} do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>INV-R</cbc:ID>
        <cbc:IssueDate>2026-09-16</cbc:IssueDate>
        <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>Доставчик</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>BG111222333</cbc:CompanyID></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        <cac:TaxTotal><cbc:TaxAmount>266.67</cbc:TaxAmount></cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:LineExtensionAmount>1333.33</cbc:LineExtensionAmount>
          <cbc:PayableAmount>1600.00</cbc:PayableAmount>
        </cac:LegalMonetaryTotal>
        <cac:InvoiceLine>
          <cbc:InvoicedQuantity unitCode="C62">2</cbc:InvoicedQuantity>
          <cbc:LineExtensionAmount>1333.33</cbc:LineExtensionAmount>
          <cac:Item><cbc:Name>Електроуреди</cbc:Name>
            <cac:ClassifiedTaxCategory><cbc:ID>S</cbc:ID><cbc:Percent>20.00</cbc:Percent></cac:ClassifiedTaxCategory>
          </cac:Item>
          <cac:Price><cbc:PriceAmount>666.67</cbc:PriceAmount></cac:Price>
        </cac:InvoiceLine>
      </Invoice>
      """

      body = json_response(post(conn, "/v1/scans/ubl", %{"xml" => xml}), 200)
      line = hd(body["lines"])
      assert line["net_amount"] == "1333.33"
      assert line["vat_amount"] == "266.67"
      assert line["total_amount"] == "1600.00"
      assert line["vat_rate"] == "20"
      assert body["total_amount"] == "1600.00"
    end

    test "празен файл и грешна посока", %{conn: conn} do
      conn = post(conn, "/v1/scans/ubl", %{})
      assert json_response(conn, 422)["detail"] == "празен файл"

      conn = post(conn, "/v1/scans/ubl", %{"xml" => @ubl, "direction" => "bogus"})
      assert json_response(conn, 422)["detail"] == "direction must be 'in' or 'out'"
    end

    test "нерегистрирана фирма абсорбира ДДС", %{conn: conn, company: company} do
      patch(conn, "/v1/companies/#{company.id}", %{"is_vat_registered" => false})
      body = json_response(post(conn, "/v1/scans/ubl", %{"xml" => @ubl}), 200)
      assert body["vat_registered"] == false
      assert body["total_vat_amount"] == "0.00"
      assert body["vat_exemption_reason"] == "VATEX-EU-SM"
      assert hd(body["lines"])["vat_rate"] == "0"
    end
  end

  describe "product-name-mappings" do
    test "запис и съпоставяне при импорт", %{conn: conn, cp: cp, goods: goods} do
      saved =
        json_response(
          post(conn, "/v1/product-name-mappings", %{
            "counterpart_id" => cp["id"],
            "items" => [%{"scanned_name" => "Стока", "product_id" => goods["id"]}]
          }),
          200
        )

      assert saved["count"] == 1

      list = json_response(get(conn, "/v1/product-name-mappings?counterpart_id=#{cp["id"]}"), 200)
      assert list["count"] == 1

      body = json_response(post(conn, "/v1/scans/ubl", %{"xml" => @ubl}), 200)
      assert hd(body["lines"])["product_id"] == goods["id"]
    end

    test "counterpart_id е задължителен", %{conn: conn} do
      conn = post(conn, "/v1/product-name-mappings", %{"items" => []})
      assert json_response(conn, 422)["detail"] == "counterpart_id е задължителен"
    end
  end

  defp write_tmp(xml) do
    path = Path.join(System.tmp_dir!(), "ubl_#{:erlang.unique_integer([:positive])}.xml")
    File.write!(path, xml)
    on_exit(fn -> File.rm(path) end)
    path
  end
end

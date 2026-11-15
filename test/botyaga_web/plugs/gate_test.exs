defmodule BotyagaWeb.Plugs.GateTest do
  use ExUnit.Case, async: true

  alias BotyagaWeb.Plugs.Gate

  describe "required_permission/2" do
    test "профил, табло и каталози са за всеки влязъл" do
      assert Gate.required_permission("GET", "/v1/me") == :any
      assert Gate.required_permission("POST", "/v1/me/password") == :any
      assert Gate.required_permission("GET", "/v1/dashboard") == :any
      assert Gate.required_permission("GET", "/v1/active-company") == :any
      assert Gate.required_permission("GET", "/v1/companies") == :any
      assert Gate.required_permission("GET", "/v1/units") == :any
      assert Gate.required_permission("GET", "/v1/saft/nomenclatures") == :any
      assert Gate.required_permission("GET", "/v1/vat-exemptions") == :any
      assert Gate.required_permission("GET", "/health") == :any
    end

    test "записите по фирмата искат право" do
      assert Gate.required_permission("POST", "/v1/companies") == {:key, "companies"}
      assert Gate.required_permission("PATCH", "/v1/companies/3") == {:key, "companies"}
      assert Gate.required_permission("DELETE", "/v1/companies/3") == {:key, "companies"}
      assert Gate.required_permission("POST", "/v1/companies/3/locations") == {:key, "companies"}
      assert Gate.required_permission("DELETE", "/v1/document-series/7") == {:key, "companies"}
      assert Gate.required_permission("GET", "/v1/companies/3/users") == {:key, "users"}
      assert Gate.required_permission("PATCH", "/v1/companies/3/users/5") == {:key, "users"}
    end

    test "модулите се слят с permission ключ" do
      assert Gate.required_permission("GET", "/v1/accounts") == {:key, "accounts"}
      assert Gate.required_permission("POST", "/v1/counterparts/vies") == {:key, "counterparts"}
      assert Gate.required_permission("GET", "/v1/product-name-mappings") == {:key, "products"}
      assert Gate.required_permission("POST", "/v1/invoices/9/post") == {:key, "invoices"}
      assert Gate.required_permission("POST", "/v1/scans/extract") == {:key, "scans"}
      assert Gate.required_permission("GET", "/v1/journal/4") == {:key, "journal"}
      assert Gate.required_permission("POST", "/v1/accounting-periods/close") == {:key, "periods"}
      assert Gate.required_permission("GET", "/v1/vat/registers") == {:key, "vat"}
      assert Gate.required_permission("POST", "/v1/bank-transactions/4/book") == {:key, "banking"}

      assert Gate.required_permission("POST", "/v1/fixed-assets/depreciation/post") ==
               {:key, "assets"}

      assert Gate.required_permission("GET", "/v1/inventory/at-location") == {:key, "stock"}
      assert Gate.required_permission("GET", "/v1/stock/rules") == {:key, "companies"}
      assert Gate.required_permission("POST", "/v1/stock/rebuild") == {:key, "stock"}
      assert Gate.required_permission("POST", "/v1/material-issues/1/confirm") == {:key, "stock"}

      assert Gate.required_permission("POST", "/v1/production-orders/2/confirm") ==
               {:key, "production"}

      assert Gate.required_permission("POST", "/v1/dividends/3/pay") == {:key, "dividends"}
      assert Gate.required_permission("GET", "/v1/reports") == {:key, "reports"}
      assert Gate.required_permission("PUT", "/v1/fs/formulas") == {:key, "reports"}
      assert Gate.required_permission("GET", "/v1/saft/export") == {:key, "saft"}

      assert Gate.required_permission("POST", "/v1/saft/movement-mappings/defaults") ==
               {:key, "saft"}

      assert Gate.required_permission("GET", "/v1/users") == {:key, "users"}
      assert Gate.required_permission("PUT", "/v1/system-settings") == {:key, "settings"}
      assert Gate.required_permission("POST", "/v1/exchange-rates/import") == {:key, "rates"}
      assert Gate.required_permission("POST", "/v1/addresses/parse") == {:key, "counterparts"}
    end

    test "одитната следа идва от модула на записа" do
      assert Gate.required_permission("GET", "/v1/audit-logs") == {:key, "reports"}
      assert Gate.required_permission("GET", "/v1/audit-logs/invoice/1") == {:key, "invoices"}
      assert Gate.required_permission("GET", "/v1/audit-logs/journal/1") == {:key, "journal"}
      assert Gate.required_permission("GET", "/v1/audit-logs/internal_doc/1") == {:key, "stock"}
      assert Gate.required_permission("GET", "/v1/audit-logs/bank_tx/1") == {:key, "banking"}
    end

    test "непознат път се отказва" do
      assert Gate.required_permission("GET", "/v1/unknown") == :unknown
      assert Gate.required_permission("POST", "/v1/auth/other") == :unknown
    end
  end
end

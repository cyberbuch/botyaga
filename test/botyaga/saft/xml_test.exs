defmodule Botyaga.Saft.XmlTest do
  use ExUnit.Case, async: true

  alias Botyaga.Saft.Xml

  test "sofia is BG-22" do
    assert Xml.region_code("София", "BG") == "BG-22"
    assert Xml.region_code("BG22", "BG") == "BG-22"
    assert Xml.region_code("Sofia", "BG") == nil
    assert Xml.region_code("", "BG") == nil
    assert Xml.region_code("Attica", "GR") == "Attica"
  end

  test "nra falls back to firm number" do
    assert {"411", _} = Xml.pack("Asset", "411")
    assert {"4532", "702"} = Xml.pack("4532", "702")
    assert Xml.pack("Liability", "12") == nil
    assert Xml.pack("0453", "0453") == nil
  end

  test "equal sides are debit" do
    zero = Xml.bal("OpeningDebitBalance", "OpeningCreditBalance", 0, 0)
    assert zero =~ "OpeningDebitBalance"
    assert zero =~ "0.00"

    credit = Xml.bal("OpeningDebitBalance", "OpeningCreditBalance", 50_000_000, 200_000_000)
    assert credit =~ "OpeningCreditBalance"
    assert credit =~ "150.00"
  end

  test "window and bucket" do
    w = Xml.window(2026, 3, 1)
    assert w.fy_start == "2026-01-01"
    assert w.start == "2026-03-01"
    assert w.next == "2026-04-01"
    assert w.prefix == "2026-03"
    assert Xml.bucket("2026-02-15", w) == :o
    assert Xml.bucket("2026-03-15", w) == :p
    assert Xml.bucket("2026-04-01", w) == nil
  end

  test "fiscal year starting mid-year" do
    w = Xml.window(2026, 2, 7)
    assert w.fy_start == "2025-07-01"
  end

  test "xml escape drops control chars and escapes markup" do
    assert Xml.xml_escape("a&b<c>d\"e") == "a&amp;b&lt;c&gt;d&quot;e"
    assert Xml.xml_escape("a\tb") == "a\tb"
    assert Xml.xml_escape("a\nb\x00c") == "abc"
  end

  test "country and cn8" do
    assert Xml.country("bg") == "BG"
    assert Xml.country("Germany") == "BG"
    assert Xml.cn8_code("", true) == "00000000"
    assert Xml.cn8_code("", false) == "0"
    assert Xml.cn8_code("12345678", false) == "12345678"
  end
end

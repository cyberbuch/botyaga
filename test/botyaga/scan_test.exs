defmodule Botyaga.ScanTest do
  use ExUnit.Case, async: true

  alias Botyaga.Scan

  @ocr ~s({"pages":[{"markdown":"Страница 1"},{"markdown":"Страница 2 - Гаранционна карта"}]})

  test "ocr_text takes only first page by default" do
    {single, n1} = Scan.ocr_text(@ocr, false)
    assert n1 == 1
    assert single == "Страница 1"

    {multi, n2} = Scan.ocr_text(@ocr, true)
    assert n2 == 2
    assert multi =~ "--- PAGE 1 ---"
    assert multi =~ "--- PAGE 2 ---"
    assert multi =~ "Страница 2 - Гаранционна карта"
  end

  test "prompt includes multipage instructions" do
    assert Scan.prompt("in", false) =~ "Only the first page"
    multi = Scan.prompt("in", true)
    assert multi =~ "MULTI-PAGE invoice"
    assert multi =~ "Гаранционна карта"
    assert Scan.prompt("out", false) =~ "This is a SALE"
  end

  test "clean_b64 strips data-uri prefix and whitespace" do
    assert Scan.clean_b64("data:application/pdf;base64,QUJD\nREVG") == "QUJDREVG"
    assert Scan.clean_b64("QUJD REVG") == "QUJDREVG"
  end

  test "mime_of and is_pdf" do
    assert Scan.mime_of("a.pdf", "") == "application/pdf"
    assert Scan.mime_of("a.png", "application/octet-stream") == "image/png"
    assert Scan.mime_of("a.jpg", "") == "image/jpeg"
    assert Scan.mime_of("a.bin", "image/webp") == "image/webp"
    assert Scan.is_pdf("a.PDF", "")
    refute Scan.is_pdf("a.png", "image/png")
  end
end

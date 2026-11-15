defmodule Botyaga.PrintingTest do
  use ExUnit.Case, async: true

  alias Botyaga.Printing

  defp sample do
    [
      {:head, "ФАКТУРА"},
      {:line, "№ 0000000001"},
      {:table, [["No", "Стока"], ["1", "Консултация <с&д>"]]}
    ]
  end

  test "names match the screen" do
    assert Printing.download_name("0000000001", "01", "pdf") == "0000000001_invoice.pdf"
    assert Printing.download_name("0000000002", "03", "docx") == "0000000002_credit_note.docx"
    assert Printing.download_name("a/b:c", "proforma", "odt") == "a_b_c_proforma.odt"
    assert Printing.download_name("   ", "01", "pdf") == "document_invoice.pdf"
    assert Printing.doc_prefix("03") == "КИ-"
    assert Printing.bg_date("2026-10-01") == "01.10.2026"
    assert Printing.bg_date("20261001") == "01.10.2026"
  end

  test "html is html5 and escapes" do
    h = Printing.html(sample())
    assert String.starts_with?(h, "<!doctype html>")
    assert h =~ "ФАКТУРА"
    assert h =~ "Консултация &lt;с&amp;д&gt;"
    assert h =~ "<table>"
  end

  test "totals are right aligned" do
    h =
      Printing.html([
        {:totals, [["Данъчна основа", "250.00 EUR"], ["ОБЩО ЗА ПЛАЩАНЕ", "300.00 EUR"]]}
      ])

    assert h =~ ~s(<table class="totals">)
    assert h =~ ~s(<td align="right">300.00 EUR</td>)
  end

  test "docx and odt are archives" do
    {:ok, docx} = Printing.render(sample(), "docx")
    {:ok, odt} = Printing.render(sample(), "odt")
    assert binary_part(docx, 0, 2) == "PK"
    assert binary_part(odt, 0, 2) == "PK"
    assert docx =~ "word/document"
    assert odt =~ "mimetype"
  end

  test "odt totals are right aligned" do
    blocks = [
      {:table, [["No", "Стока"]]},
      {:totals, [["Данъчна основа", "250.00 EUR"], ["ОБЩО ЗА ПЛАЩАНЕ", "300.00 EUR"]]}
    ]

    {:ok, odt} = Printing.render(blocks, "odt")
    assert odt =~ ~s(fo:text-align="end")
    assert odt =~ ~s(table:style-name="TotalsRight")
  end

  test "invalid format is rejected" do
    assert {:error, {422, _}} = Printing.render(sample(), "bogus")
  end
end

defmodule Botyaga.Printing.Office do
  @moduledoc """
  DOCX и ODT от block-ове, нативно (`:zip` + XML), без външни библиотеки.
  DOCX е OOXML (`word/document.xml`), ODT е ODF (`content.xml`) — виж `Office.Odt`.
  Шрифтът DejaVu Sans се referира по име; рендерът го взима от системата/sidecar-а.
  """

  alias Botyaga.Printing
  alias Botyaga.Zip

  @font "DejaVu Sans"

  def convert(blocks, "docx"), do: {:ok, docx(blocks)}
  def convert(blocks, "odt"), do: Botyaga.Printing.Office.Odt.convert(blocks)
  def convert(_blocks, _), do: {:error, {422, "format трябва да е docx или odt"}}

  defp docx(blocks) do
    body = Enum.map_join(blocks, &block/1)

    document =
      ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
        ~s(<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">) <>
        "<w:body>#{body}" <>
        ~s(<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>) <>
        ~s(<w:pgMar w:top="1021" w:right="794" w:bottom="1021" w:left="794"/></w:sectPr>) <>
        "</w:body></w:document>"

    Zip.pack([
      {"[Content_Types].xml", content_types()},
      {"_rels/.rels", root_rels()},
      {"word/document.xml", document}
    ])
  end

  defp block({:head, t}), do: paragraph(t, center: true, bold: true, sz: 30)
  defp block({:line, ""}), do: "<w:p/>"
  defp block({:line, t}), do: paragraph(t, sz: 20)
  defp block({:table, rows}), do: table(rows, false)
  defp block({:totals, rows}), do: table(rows, true)

  defp paragraph(text, opts) do
    jc = if opts[:center], do: ~s(<w:jc w:val="center"/>), else: ""
    sz = opts[:sz] || 20
    bold = if opts[:bold], do: "<w:b/>", else: ""
    rpr = "#{bold}<w:sz w:val=\"#{sz}\"/><w:rFonts w:ascii=\"#{@font}\" w:hAnsi=\"#{@font}\"/>"

    "<w:p><w:pPr>#{jc}<w:rPr>#{bold}<w:sz w:val=\"#{sz}\"/></w:rPr></w:pPr>" <>
      "<w:r><w:rPr>#{rpr}</w:rPr><w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r></w:p>"
  end

  defp table(rows, totals?) do
    cols = rows |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    n = max(cols, 1)
    # A4 (11906 twips) минус полета 14mm×2 (1588) = 10318; totals са 60%.
    avail = if totals?, do: 6190, else: 10318
    col_w = div(avail, n)
    grid = Enum.map_join(1..n, fn _ -> ~s(<w:gridCol w:w="#{col_w}"/>) end)

    borders =
      if totals?,
        do: ~s(<w:top w:val="single" w:sz="4" w:color="999999"/>),
        else:
          ~s(<w:top w:val="single" w:sz="4" w:color="999999"/>) <>
            ~s(<w:left w:val="single" w:sz="4" w:color="999999"/>) <>
            ~s(<w:bottom w:val="single" w:sz="4" w:color="999999"/>) <>
            ~s(<w:right w:val="single" w:sz="4" w:color="999999"/>) <>
            ~s(<w:insideH w:val="single" w:sz="4" w:color="999999"/>) <>
            ~s(<w:insideV w:val="single" w:sz="4" w:color="999999"/>)

    width =
      if totals?,
        do: ~s(<w:tblW w:w="3000" w:type="pct"/>),
        else: ~s(<w:tblW w:w="5000" w:type="pct"/>)

    jc = if totals?, do: ~s(<w:jc w:val="right"/>), else: ""

    trs =
      rows
      |> Enum.with_index()
      |> Enum.map_join(fn {row, ri} ->
        cells =
          row
          |> Enum.with_index()
          |> Enum.map_join(fn {cell, ci} ->
            header? = not totals? and ri == 0
            right? = totals? and ci + 1 == length(row)
            cell_xml(cell, header?, right?, col_w)
          end)

        "<w:tr>#{cells}</w:tr>"
      end)

    "<w:tbl><w:tblPr>#{width}#{jc}<w:tblLayout w:type=\"autofit\"/><w:tblBorders>#{borders}</w:tblBorders></w:tblPr>" <>
      "<w:tblGrid>#{grid}</w:tblGrid>#{trs}</w:tbl>"
  end

  defp cell_xml(text, header?, right?, col_w) do
    shade = if header?, do: ~s(<w:shd w:val="clear" w:fill="EEF6F2"/>), else: ""
    jc = if right?, do: ~s(<w:jc w:val="right"/>), else: ""
    bold = if header?, do: "<w:b/>", else: ""
    rpr = "#{bold}<w:sz w:val=\"20\"/><w:rFonts w:ascii=\"#{@font}\" w:hAnsi=\"#{@font}\"/>"

    "<w:tc><w:tcPr><w:tcW w:w=\"#{col_w}\" w:type=\"dxa\"/>#{shade}</w:tcPr>" <>
      "<w:p><w:pPr>#{jc}<w:rPr>#{bold}<w:sz w:val=\"20\"/></w:rPr></w:pPr>" <>
      "<w:r><w:rPr>#{rpr}</w:rPr><w:t xml:space=\"preserve\">#{esc(text)}</w:t></w:r></w:p></w:tc>"
  end

  defp esc(s), do: Printing.xml_escape(s)

  defp content_types do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) <>
      ~s(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) <>
      ~s(<Default Extension="xml" ContentType="application/xml"/>) <>
      ~s(<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>) <>
      "</Types>"
  end

  defp root_rels do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) <>
      ~s(<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>) <>
      "</Relationships>"
  end
end

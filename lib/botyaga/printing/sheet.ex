defmodule Botyaga.Printing.Sheet do
  @moduledoc """
  XLSX и ODS от таблица (grid). ZIP е без компресия, за да мине кирилицата като
  UTF-8. Числата са числови клетки; `bg` ги показва в български формат (1 200,00).
  Порт на `reports_sheet.rs`.
  """

  alias Botyaga.Printing
  alias Botyaga.Zip

  def xlsx(grid, bg) do
    sheet = worksheet(grid)
    styles = xlsx_styles(grid, bg)

    Zip.pack([
      {"[Content_Types].xml", content_types()},
      {"_rels/.rels", root_rels()},
      {"xl/workbook.xml", workbook()},
      {"xl/_rels/workbook.xml.rels", workbook_rels()},
      {"xl/styles.xml", styles},
      {"xl/worksheets/sheet1.xml", sheet}
    ])
  end

  def ods(grid, bg) do
    content = ods_content(grid, bg)

    Zip.pack([
      {"mimetype", "application/vnd.oasis.opendocument.spreadsheet"},
      {"META-INF/manifest.xml", ods_manifest()},
      {"content.xml", content}
    ])
  end

  defp worksheet(grid) do
    styles = style_index(grid)

    rows =
      grid
      |> Enum.with_index()
      |> Enum.map_join(fn {row, r} ->
        n = r + 1

        cells =
          row
          |> Enum.with_index()
          |> Enum.map_join(fn {cell, c} ->
            ref = "#{col_name(c)}#{n}"

            case number(cell) do
              nil ->
                ~s(<c r="#{ref}" t="inlineStr"><is><t xml:space="preserve">#{esc(cell)}</t></is></c>)

              num ->
                s = Map.get(styles, num.dp, 0)
                ~s(<c r="#{ref}" s="#{s}"><v>#{num.value}</v></c>)
            end
          end)

        "<row r=\"#{n}\">#{cells}</row>"
      end)

    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">) <>
      "<sheetData>#{rows}</sheetData></worksheet>"
  end

  defp ods_content(grid, bg) do
    rows =
      Enum.map_join(grid, fn row ->
        cells =
          Enum.map_join(row, fn cell ->
            case number(cell) do
              nil ->
                ~s(<table:table-cell office:value-type="string"><text:p>#{esc(cell)}</text:p></table:table-cell>)

              num ->
                style = if num.dp == 4, do: "Num4", else: "Num2"
                text = if bg, do: num.bg_text, else: cell

                ~s(<table:table-cell table:style-name="#{style}" office:value-type="float" ) <>
                  ~s(office:value="#{num.value}"><text:p>#{esc(text)}</text:p></table:table-cell>)
            end
          end)

        "<table:table-row>#{cells}</table:table-row>"
      end)

    locale = if bg, do: ~s( number:language="bg" number:country="BG"), else: ""

    ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
      ~s(<office:document-content ) <>
      ~s(xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ) <>
      ~s(xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ) <>
      ~s(xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" ) <>
      ~s(xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ) <>
      ~s(xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">) <>
      "<office:automatic-styles>" <>
      ~s(<number:number-style style:name="N2"#{locale}>) <>
      ~s(<number:number number:decimal-places="2" number:min-decimal-places="2" number:grouping="true"/>) <>
      "</number:number-style>" <>
      ~s(<number:number-style style:name="N4"#{locale}>) <>
      ~s(<number:number number:decimal-places="4" number:min-decimal-places="4" number:grouping="true"/>) <>
      "</number:number-style>" <>
      ~s(<style:style style:name="Num2" style:family="table-cell" style:data-style-name="N2"/>) <>
      ~s(<style:style style:name="Num4" style:family="table-cell" style:data-style-name="N4"/>) <>
      "</office:automatic-styles>" <>
      ~s(<office:body><office:spreadsheet>) <>
      ~s(<table:table table:name="Spravka">#{rows}</table:table>) <>
      "</office:spreadsheet></office:body></office:document-content>"
  end

  defp col_name(index), do: col_name(index, "")

  defp col_name(index, acc) do
    acc = <<65 + rem(index, 26)>> <> acc
    if index < 26, do: acc, else: col_name(Kernel.div(index, 26) - 1, acc)
  end

  @doc "Разпознава суми и количества: цифри, по избор групирани с интервал, и задължителна десетична част."
  def number(s) do
    t = String.trim(s || "")

    {neg, body} =
      if String.starts_with?(t, "-"), do: {true, String.slice(t, 1..-1//1)}, else: {false, t}

    with [int_part, frac] <- String.split(body, ".", parts: 2),
         true <- frac != "" and String.length(frac) <= 6 and String.match?(frac, ~r/^[0-9]+$/),
         true <- String.match?(int_part, ~r/^[0-9 ]+$/),
         int_digits <- String.replace(int_part, " ", ""),
         true <- int_digits != "" do
      sign = if neg, do: "-", else: ""
      len = String.length(int_digits)

      grouped =
        int_digits
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.map_join(fn {c, i} ->
          if i > 0 and rem(len - i, 3) == 0, do: " " <> c, else: c
        end)

      %{
        value: "#{sign}#{int_digits}.#{frac}",
        dp: String.length(frac),
        bg_text: "#{sign}#{grouped},#{frac}"
      }
    else
      _ -> nil
    end
  end

  defp style_index(grid) do
    {map, _n} =
      Enum.reduce(grid, {%{}, 0}, fn row, {map, n} ->
        Enum.reduce(row, {map, n}, fn cell, {map, n} ->
          case number(cell) do
            nil ->
              {map, n}

            num ->
              if Map.has_key?(map, num.dp),
                do: {map, n},
                else: {Map.put(map, num.dp, n + 1), n + 1}
          end
        end)
      end)

    map
  end

  defp xlsx_styles(grid, bg) do
    entries = grid |> style_index() |> Enum.sort_by(fn {_dp, style} -> style end)
    locale = if bg, do: "[$-402]", else: ""

    {num_fmts, xfs, count} =
      Enum.reduce(entries, {"", "", 0}, fn {dp, style}, {nf, xf, count} ->
        id = 176 + style
        zeros = String.duplicate("0", dp)

        nf =
          nf <>
            ~s(<numFmt numFmtId="#{id}" formatCode="#{locale}#,##0.#{zeros}"/>)

        xf =
          xf <>
            ~s(<xf numFmtId="#{id}" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>)

        {nf, xf, count + 1}
      end)

    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">) <>
      ~s(<numFmts count="#{count}">#{num_fmts}</numFmts>) <>
      ~s(<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>) <>
      ~s(<fills count="1"><fill><patternFill patternType="none"/></fill></fills>) <>
      ~s(<borders count="1"><border/></borders>) <>
      ~s(<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>) <>
      ~s(<cellXfs count="#{count + 1}"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>#{xfs}</cellXfs>) <>
      "</styleSheet>"
  end

  defp esc(s), do: Printing.xml_escape(s)

  defp content_types do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) <>
      ~s(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) <>
      ~s(<Default Extension="xml" ContentType="application/xml"/>) <>
      ~s(<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>) <>
      ~s(<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) <>
      "</Types>"
  end

  defp root_rels do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) <>
      ~s(<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>) <>
      "</Relationships>"
  end

  defp workbook do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ) <>
      ~s(xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">) <>
      ~s(<sheets><sheet name="Spravka" sheetId="1" r:id="rId1"/></sheets></workbook>)
  end

  defp workbook_rels do
    ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>) <>
      ~s(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) <>
      ~s(<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>) <>
      "</Relationships>"
  end

  defp ods_manifest do
    ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
      ~s(<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">) <>
      ~s(<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>) <>
      ~s(<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>) <>
      "</manifest:manifest>"
  end
end

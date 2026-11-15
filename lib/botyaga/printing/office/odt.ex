defmodule Botyaga.Printing.Office.Odt do
  @moduledoc """
  ODT (ODF text) от block-ове. Дясното подравняване на тоталите е в стила
  `TotalsRight` (`fo:text-align="end"`) — същият резултат като post-обработката
  на `report.rs#odt_align_totals`, но приложено директно при генерацията.
  """

  alias Botyaga.Printing
  alias Botyaga.Zip

  @font "DejaVu Sans"

  def convert(blocks) do
    body = Enum.map_join(blocks, &block/1)

    content =
      ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
        ~s(<office:document-content ) <>
        ~s(xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ) <>
        ~s(xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ) <>
        ~s(xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ) <>
        ~s(xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ) <>
        ~s(xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.2">) <>
        "<office:automatic-styles>#{styles()}</office:automatic-styles>" <>
        "<office:body><office:text>#{body}</office:text></office:body></office:document-content>"

    {:ok,
     Zip.pack([
       {"mimetype", "application/vnd.oasis.opendocument.text"},
       {"META-INF/manifest.xml", manifest()},
       {"content.xml", content}
     ])}
  end

  defp block({:head, t}),
    do: ~s(<text:h text:style-name="Head" text:outline-level="1">#{esc(t)}</text:h>)

  defp block({:line, ""}), do: ~s(<text:p text:style-name="Gap"/>)
  defp block({:line, t}), do: ~s(<text:p text:style-name="Line">#{esc(t)}</text:p>)
  defp block({:table, rows}), do: table(rows, false)
  defp block({:totals, rows}), do: table(rows, true)

  defp table(rows, totals?) do
    cols = rows |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    columns = ~s(<table:table-column table:number-columns-repeated="#{max(cols, 1)}"/>)
    style = if totals?, do: "TotalsTbl", else: "Tbl"

    trs =
      rows
      |> Enum.with_index()
      |> Enum.map_join(fn {row, ri} ->
        cells =
          row
          |> Enum.with_index()
          |> Enum.map_join(fn {cell, ci} ->
            cell_style =
              cond do
                totals? and ci + 1 == length(row) -> "TotalsRight"
                totals? -> "TotalsCell"
                ri == 0 -> "HeadCell"
                true -> "Cell"
              end

            ~s(<table:table-cell table:style-name="#{cell_style}" office:value-type="string">) <>
              ~s(<text:p>#{esc(cell)}</text:p></table:table-cell>)
          end)

        "<table:table-row>#{cells}</table:table-row>"
      end)

    ~s(<table:table table:style-name="#{style}">#{columns}#{trs}</table:table>)
  end

  defp styles do
    cell_border = ~s(fo:border="0.5pt solid #999999" fo:padding="3pt 5pt")

    top_only =
      ~s(fo:border-top="0.5pt solid #999999" fo:border-bottom="none" fo:border-left="none" fo:border-right="none")

    ~s(<style:style style:name="Head" style:family="paragraph">) <>
      ~s(<style:paragraph-properties fo:text-align="center" fo:margin-bottom="6pt"/>) <>
      ~s(<style:text-properties fo:font-size="15pt" fo:font-weight="bold" style:font-name="#{@font}"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="Line" style:family="paragraph">) <>
      ~s(<style:paragraph-properties fo:margin-bottom="3pt"/>) <>
      ~s(<style:text-properties fo:font-size="10pt" style:font-name="#{@font}"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="Gap" style:family="paragraph">) <>
      ~s(<style:paragraph-properties fo:margin-bottom="6pt"/>) <>
      ~s(<style:text-properties fo:font-size="6pt"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="Tbl" style:family="table">) <>
      ~s(<style:table-properties table:align="margins" style:width="100%"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="TotalsTbl" style:family="table">) <>
      ~s(<style:table-properties table:align="right" style:width="60%"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="Cell" style:family="table-cell">) <>
      ~s(<style:table-cell-properties #{cell_border}/>) <>
      ~s(<style:text-properties fo:font-size="10pt" style:font-name="#{@font}"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="HeadCell" style:family="table-cell">) <>
      ~s(<style:table-cell-properties #{cell_border} fo:background-color="#eef6f2"/>) <>
      ~s(<style:text-properties fo:font-size="10pt" fo:font-weight="bold" style:font-name="#{@font}"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="TotalsCell" style:family="table-cell">) <>
      ~s(<style:table-cell-properties #{top_only}/>) <>
      ~s(<style:text-properties fo:font-size="10pt" style:font-name="#{@font}"/>) <>
      "</style:style>" <>
      ~s(<style:style style:name="TotalsRight" style:family="table-cell">) <>
      ~s(<style:table-cell-properties #{top_only}/>) <>
      ~s(<style:paragraph-properties fo:text-align="end"/>) <>
      ~s(<style:text-properties fo:font-size="10pt" style:font-name="#{@font}"/>) <>
      "</style:style>"
  end

  defp manifest do
    ~s(<?xml version="1.0" encoding="UTF-8"?>) <>
      ~s(<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">) <>
      ~s(<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>) <>
      ~s(<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>) <>
      "</manifest:manifest>"
  end

  defp esc(s), do: Printing.xml_escape(s)
end

defmodule Botyaga.Printing do
  @moduledoc """
  Печат на документ: PDF, DOCX и ODT. Един HTML5 документ към PDF (Chromium
  sidecar) и офис документи (нативно). Порт на `report.rs` и `print_sheet.rs`.
  Block-ове: `{:head, t}`, `{:line, t}`, `{:table, rows}`, `{:totals, rows}`.
  """

  alias Botyaga.Printing.{Office, Pdf}

  @style """
  @page { size: A4; margin: 18mm 14mm; }
  body { font-family: DejaVu, sans-serif; font-size: 10pt; color: #17211c; }
  h1 { font-size: 15pt; text-align: center; margin: 0 0 6pt; }
  p { margin: 0 0 3pt; }
  p.gap { height: 6pt; }
  table { width: 100%; border-collapse: collapse; margin: 0 0 8pt; }
  th, td { border: 1px solid #999; padding: 3pt 5pt; text-align: left; vertical-align: top; }
  th { background: #eef6f2; font-weight: bold; }
  table.totals { width: 60%; margin-left: auto; }
  table.totals td { border: none; border-top: 1px solid #999; }
  table.totals td+td { text-align: right; }
  """

  def render(blocks, format) do
    case format do
      "pdf" -> Pdf.convert(html(blocks))
      f when f in ["docx", "odt"] -> Office.convert(blocks, f)
      _ -> {:error, {422, "format трябва да е pdf/docx/odt"}}
    end
  end

  @doc "Нормализира формата (празен → pdf) и го валидира."
  def check_format(raw) do
    f = String.trim(raw || "")
    f = if f == "", do: "pdf", else: f

    if f in ["pdf", "docx", "odt"],
      do: {:ok, f},
      else: {:error, {422, "format трябва да е pdf/docx/odt"}}
  end

  def html(blocks) do
    body = Enum.map_join(blocks, &block_html/1)

    "<!doctype html><html lang=\"bg\"><head><meta charset=\"utf-8\">" <>
      "<style>#{@style}</style></head><body>#{body}</body></html>"
  end

  defp block_html({:head, t}), do: "<h1>#{xml_escape(t)}</h1>"
  defp block_html({:line, ""}), do: "<p class=\"gap\"></p>"
  defp block_html({:line, t}), do: "<p>#{xml_escape(t)}</p>"
  defp block_html({:table, rows}), do: table_html(rows)
  defp block_html({:totals, rows}), do: totals_html(rows)

  defp table_html(rows) do
    inner =
      rows
      |> Enum.with_index()
      |> Enum.map_join(fn {row, i} ->
        tag = if i == 0, do: "th", else: "td"
        cells = Enum.map_join(row, &"<#{tag}>#{xml_escape(&1)}</#{tag}>")
        "<tr>#{cells}</tr>"
      end)

    "<table>#{inner}</table>"
  end

  defp totals_html(rows) do
    inner =
      Enum.map_join(rows, fn row ->
        cells =
          row
          |> Enum.with_index()
          |> Enum.map_join(fn {cell, i} ->
            if i + 1 == length(row),
              do: "<td align=\"right\">#{xml_escape(cell)}</td>",
              else: "<td>#{xml_escape(cell)}</td>"
          end)

        "<tr>#{cells}</tr>"
      end)

    "<table class=\"totals\">#{inner}</table>"
  end

  def mime("docx"), do: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  def mime("odt"), do: "application/vnd.oasis.opendocument.text"
  def mime(_), do: "application/pdf"

  def download_name(number, document_type, ext),
    do: "#{safe_name(number)}_#{file_slug(document_type)}.#{ext}"

  def safe_name(s) do
    t =
      s
      |> String.graphemes()
      |> Enum.map_join(fn c ->
        cond do
          c in ["\"", "/", "\\", ":", "*", "?", "<", ">", "|"] -> "_"
          control?(c) -> "_"
          true -> c
        end
      end)
      |> String.trim()

    if t == "", do: "document", else: t
  end

  defp control?(c) do
    case c do
      <<cp::utf8>> -> cp < 32 or cp == 127
      _ -> false
    end
  end

  def file_slug(t) do
    case t do
      "02" -> "debit_note"
      "03" -> "credit_note"
      "04" -> "call_off_dispatch"
      "05" -> "call_off_receipt"
      "07" -> "customs_declaration"
      "09" -> "protocol"
      "11" -> "invoice_cash"
      "12" -> "debit_note_cash"
      "13" -> "credit_note_cash"
      "23" -> "credit_note_126b"
      "29" -> "protocol_126b"
      "50" -> "fuel_protocol"
      "81" -> "sales_report"
      "82" -> "sales_report_special"
      "83" -> "sales_report_fuel"
      "84" -> "sales_report_bread"
      "85" -> "sales_report_flour"
      "91" -> "vat_protocol"
      "92" -> "vat_protocol_credit"
      "93" -> "vat_protocol_151v"
      "94" -> "vat_protocol_151v_scheme"
      "95" -> "food_protocol"
      "proforma" -> "proforma"
      _ -> "invoice"
    end
  end

  def doc_title(t) do
    case t do
      "02" -> "ДЕБИТНО ИЗВЕСТИЕ"
      "03" -> "КРЕДИТНО ИЗВЕСТИЕ"
      t when t in ["04", "05"] -> "РЕГИСТЪР НА СТОКИ ПОД РЕЖИМ СКЛАДИРАНЕ ДО ПОИСКВАНЕ"
      "07" -> "МИТНИЧЕСКА ДЕКЛАРАЦИЯ"
      "09" -> "ПРОТОКОЛ ПО ЧЛ. 117 ОТ ЗДДС"
      "11" -> "ФАКТУРА - КАСОВА ОТЧЕТНОСТ"
      "12" -> "ДЕБИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ"
      "13" -> "КРЕДИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ"
      "23" -> "КРЕДИТНО ИЗВЕСТИЕ ПО ЧЛ. 126Б, АЛ. 1 ОТ ЗДДС"
      "29" -> "ПРОТОКОЛ ПО ЧЛ. 126Б, АЛ. 2 И 7 ОТ ЗДДС"
      t when t in ["81", "83", "84", "85"] -> "ОТЧЕТ ЗА ИЗВЪРШЕНИТЕ ПРОДАЖБИ"
      "82" -> "ОТЧЕТ ЗА ПРОДАЖБИ ПРИ СПЕЦИАЛЕН РЕД НА ОБЛАГАНЕ"
      "proforma" -> "ПРОФОРМА ФАКТУРА"
      _ -> "ФАКТУРА"
    end
  end

  def doc_prefix(t) do
    case t do
      t when t in ["02", "12"] -> "ДИ-"
      t when t in ["03", "13", "23"] -> "КИ-"
      "proforma" -> "ПФ-"
      _ -> ""
    end
  end

  def bg_date(raw) do
    s = String.trim(raw || "")

    cond do
      String.length(s) >= 10 and ascii?(String.slice(s, 0, 10)) and
        String.slice(s, 4, 1) == "-" and String.slice(s, 7, 1) == "-" ->
        "#{String.slice(s, 8, 2)}.#{String.slice(s, 5, 2)}.#{String.slice(s, 0, 4)}"

      String.length(s) >= 8 and String.match?(String.slice(s, 0, 8), ~r/^[0-9]{8}$/) ->
        "#{String.slice(s, 6, 2)}.#{String.slice(s, 4, 2)}.#{String.slice(s, 0, 4)}"

      true ->
        s
    end
  end

  defp ascii?(s), do: String.match?(s, ~r/^[\x00-\x7F]*$/)

  def xml_escape(s) do
    (s || "")
    |> String.replace(~r/[\x00-\x08\x0A-\x1F\x7F-\x9F]/u, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

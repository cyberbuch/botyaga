defmodule Botyaga.Scan do
  @moduledoc """
  Сканиране на фактура: Mistral OCR, после JSON за чернова. Порт на `scan.rs`.
  Ключът е в настройките на фирмата; без него extract връща 422.
  """

  alias Botyaga.{Addr, Mistral, Params, Pnmap}
  alias Botyaga.Pnmap.Absorb

  def extract(company_id, params) do
    filename = params |> str("filename") |> or_default("document.pdf")
    mime = str(params, "mime")
    direction = params |> str("direction") |> or_default("in") |> String.trim()
    multipage = (Params.flag(params, "multipage") || 0) != 0

    cond do
      direction not in ["in", "out"] ->
        {:error, {422, "direction must be 'in' or 'out'"}}

      true ->
        with {:ok, b64} <- required(params, "content_base64") do
          vat_registered = Pnmap.company_vat_registered(company_id)
          key = Addr.mistral_key(company_id)

          if key == "" do
            {:error,
             {422, "Няма Mistral ключ в настройките на фирмата (Настройки → Интеграции)."}}
          else
            with {:ok, {text, pages_scanned}} <- ocr(key, filename, mime, b64, multipage),
                 {:ok, doc} <- extract_json(key, direction, multipage, text) do
              {:ok,
               preview(
                 company_id,
                 doc,
                 filename,
                 direction,
                 multipage,
                 pages_scanned,
                 vat_registered
               )}
            end
          end
        end
    end
  end

  defp preview(company_id, doc, filename, direction, multipage, pages_scanned, vat_registered) do
    vat = str_field(doc, "counterpart_vat_number", "")
    eik = str_field(doc, "counterpart_eik", "")
    hit = Pnmap.counterpart_hit(company_id, vat, eik)
    raw_lines = Map.get(doc, "lines") || []

    lines =
      Enum.map(raw_lines, fn line ->
        desc = str_field(line, "description", "")
        total = str_field(line, "total_amount", "")
        total = if total == "", do: str_field(line, "total", "0"), else: total
        pid = if hit, do: Pnmap.product_for(company_id, hit.id, desc, ""), else: 0

        item = %{
          "description" => desc,
          "quantity" => str_field(line, "quantity", "1"),
          "unit" => str_field(line, "unit", "C62"),
          "unit_price" => str_field(line, "unit_price", "0"),
          "vat_rate" => str_field(line, "vat_rate", "20"),
          "net_amount" => str_field(line, "net_amount", ""),
          "vat_amount" => str_field(line, "vat_amount", ""),
          "total_amount" => total
        }

        if pid > 0, do: Map.put(item, "product_id", pid), else: item
      end)

    tot_net = str_field(doc, "total_net_amount", "0")
    tot_vat = str_field(doc, "total_vat_amount", "0")
    tot_all = str_field(doc, "total_amount", "0")
    vatex = str_field(doc, "vat_exemption_reason", "")

    {lines, tot_net, tot_vat, tot_all, vatex} =
      if vat_registered do
        {lines, tot_net, tot_vat, tot_all, vatex}
      else
        {lines, tot_net, tot_vat, tot_all} =
          if direction == "in" do
            {lines, net, all} = Absorb.absorb(lines, tot_net, tot_vat, tot_all)
            {lines, net, "0.00", all}
          else
            lines =
              Enum.map(lines, fn line ->
                line
                |> Map.put("vat_rate", "0")
                |> Map.put("vat_amount", "0.00")
                |> Map.put("total_amount", Map.get(line, "net_amount"))
              end)

            {lines, tot_net, "0.00", tot_net}
          end

        vatex = if String.trim(vatex) == "", do: "VATEX-EU-SM", else: vatex
        {lines, tot_net, tot_vat, tot_all, vatex}
      end

    original = str_field(doc, "original_invoice_number", "")
    original_id = Pnmap.invoice_by_number(company_id, original)

    out = %{
      direction: direction,
      filename: filename,
      multipage: multipage,
      pages_scanned: pages_scanned,
      vat_registered: vat_registered,
      invoice_number: str_field(doc, "invoice_number", ""),
      issue_date: str_field(doc, "issue_date", ""),
      due_date: str_field(doc, "due_date", ""),
      tax_event_date: str_field(doc, "tax_event_date", ""),
      document_type: str_field(doc, "document_type", "01"),
      counterpart_name: str_field(doc, "counterpart_name", ""),
      counterpart_eik: eik,
      counterpart_vat_number: vat,
      currency: str_field(doc, "currency", "EUR"),
      currency_rate: str_field(doc, "currency_rate", "1"),
      payment_method: str_field(doc, "payment_method", "банков превод"),
      payment_note: str_field(doc, "payment_note", ""),
      vat_exemption_reason: vatex,
      original_invoice_number: original,
      total_net_amount: tot_net,
      total_vat_amount: tot_vat,
      total_amount: tot_all,
      lines: lines
    }

    out = if original_id > 0, do: Map.put(out, :original_invoice_id, original_id), else: out

    if hit do
      out
      |> Map.put(:counterpart_id, hit.id)
      |> Map.put(:counterpart, %{id: hit.id, name: hit.name, eik: hit.eik, vat_number: hit.vat})
    else
      out
    end
  end

  defp ocr(key, filename, mime, b64, multipage) do
    raw = clean_b64(b64)

    if raw == "" do
      {:error, {422, "празен файл"}}
    else
      mt = mime_of(filename, mime)
      data = "data:#{mt};base64,#{raw}"
      pdf = is_pdf(filename, mt)

      document =
        if pdf,
          do: %{type: "document_url", document_url: data},
          else: %{type: "image_url", image_url: data}

      body = %{model: "mistral-ocr-latest", document: document, include_image_base64: false}
      body = if pdf and not multipage, do: Map.put(body, :pages, [0]), else: body

      case Mistral.post_json("https://api.mistral.ai/v1/ocr", key, body, 120) do
        {:ok, 200, text} ->
          {markdown, count} = ocr_text(text, multipage)

          if markdown == "",
            do: {:error, {502, "OCR не върна текст от документа"}},
            else: {:ok, {markdown, count}}

        {:ok, status, _} ->
          {:error, {502, "Mistral OCR върна статус #{status}"}}

        {:error, _} ->
          {:error,
           {502,
            "Mistral OCR: връзката към api.mistral.ai се скъса (TLS/таймаут). Опитай по-малък файл."}}
      end
    end
  end

  defp extract_json(key, direction, multipage, text) do
    body = %{
      model: "mistral-small-2603",
      temperature: 0.1,
      max_tokens: 4096,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You extract Bulgarian invoices. Return only JSON."},
        %{role: "user", content: "#{prompt(direction, multipage)}\n\nOCR text:\n#{text}"}
      ]
    }

    case Mistral.post_json("https://api.mistral.ai/v1/chat/completions", key, body, 60) do
      {:ok, 200, raw} ->
        parse_invoice(chat_content(raw))

      {:ok, status, _} ->
        {:error, {502, "Mistral chat върна статус #{status}"}}

      {:error, _} ->
        {:error, {502, "Mistral chat е недостъпен (мрежова грешка)"}}
    end
  end

  defp parse_invoice(content) do
    with {start, _} <- :binary.match(content, "{"),
         matches when matches != [] <- :binary.matches(content, "}"),
         {end_pos, _} <- List.last(matches),
         {:ok, doc} <- Jason.decode(binary_part(content, start, end_pos - start + 1)) do
      {:ok, doc}
    else
      :nomatch -> {:error, {502, "Mistral не върна JSON на фактурата"}}
      [] -> {:error, {502, "Mistral не върна JSON на фактурата"}}
      {:error, _} -> {:error, {502, "невалиден JSON от Mistral"}}
      _ -> {:error, {502, "Mistral не върна JSON на фактурата"}}
    end
  end

  defp chat_content(body) do
    case Jason.decode(body) do
      {:ok, doc} -> get_in(doc, ["choices", Access.at(0), "message", "content"]) || ""
      _ -> ""
    end
  end

  def ocr_text(body, multipage) do
    case Jason.decode(body) do
      {:ok, doc} ->
        pages = Map.get(doc, "pages") || []
        total = length(pages)
        limit = if multipage, do: total, else: 1

        text =
          pages
          |> Enum.take(limit)
          |> Enum.with_index()
          |> Enum.flat_map(fn {p, i} ->
            md = p |> Map.get("markdown", "") |> to_string() |> String.trim()

            cond do
              md == "" -> []
              multipage and total > 1 -> ["--- PAGE #{i + 1} ---\n#{md}"]
              true -> [md]
            end
          end)
          |> Enum.join("\n\n")

        {text, min(limit, total)}

      _ ->
        {"", 0}
    end
  end

  def prompt(direction, multipage) do
    who =
      if direction == "in",
        do: "This is a PURCHASE: counterpart is the supplier (issuer of the invoice).",
        else: "This is a SALE: counterpart is the customer (recipient), not our company."

    page_hint =
      if multipage,
        do:
          " The user explicitly marked this as a MULTI-PAGE invoice: combine all continuation invoice line items across pages and take final totals from the last invoice page. CRITICAL: Ignore any duplicate copies of the same invoice (e.g. second page marked 'КОПИЕ' / 'COPY' repeating the same lines), warranty cards ('Гаранционна карта'), delivery/handover protocols ('Приемо-предавателен протокол' / 'Стокова разписка'), or general terms.",
        else: " Only the first page of the document is scanned."

    "Extract a Bulgarian invoice as JSON only. Keys: invoice_number, issue_date (YYYY-MM-DD), due_date, " <>
      "document_type (01 invoice, 02 debit note, 03 credit note), counterpart_name, counterpart_eik (digits only), " <>
      "counterpart_vat_number (with country prefix e.g. BG), currency, currency_rate, payment_method, payment_note, " <>
      "vat_exemption_reason, tax_event_date, original_invoice_number, total_net_amount, total_vat_amount, total_amount, " <>
      "lines (array of description, quantity, unit, unit_price, vat_rate, net_amount, vat_amount, total_amount). " <>
      "Amounts as strings with 2 decimals. unit_price is net without VAT. unit is UN/CEFACT (C62 pcs, KGM kg, LTR litre, MTR metre) else C62. " <>
      "vat_rate is 20, 9 or 0. Empty string if unknown. #{who}#{page_hint}"
  end

  def clean_b64(raw) do
    head = String.slice(raw || "", 0, 80)

    body =
      if String.contains?(head, "base64") do
        case :binary.match(raw, ",") do
          {pos, _} -> binary_part(raw, pos + 1, byte_size(raw) - pos - 1)
          :nomatch -> raw
        end
      else
        raw
      end

    String.replace(body || "", ~r/\s/, "")
  end

  def mime_of(filename, mime) do
    m = String.trim(mime || "")

    if m != "" and m != "application/octet-stream" do
      m
    else
      lower = String.downcase(filename || "")

      cond do
        String.ends_with?(lower, ".pdf") -> "application/pdf"
        String.ends_with?(lower, ".png") -> "image/png"
        String.ends_with?(lower, ".webp") -> "image/webp"
        true -> "image/jpeg"
      end
    end
  end

  def is_pdf(filename, mime),
    do: mime == "application/pdf" or String.ends_with?(String.downcase(filename || ""), ".pdf")

  defp str_field(v, key, default) do
    case Map.get(v, key) do
      nil ->
        default

      value ->
        s = value |> to_string() |> String.trim()
        if s == "", do: default, else: s
    end
  end

  defp or_default(value, fallback), do: if(String.trim(value) == "", do: fallback, else: value)

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

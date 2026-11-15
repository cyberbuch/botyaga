defmodule Botyaga.Ubl.Import do
  @moduledoc """
  UBL XML към същия преглед като сканирането. Черновата се записва после с
  фактурата. Порт на `ubl_in.rs`: избор на посока, съпоставяне на контрагент и
  артикули, абсорбиране на ДДС при нерегистрирана фирма.
  """

  alias Botyaga.{Companies, Params, Pnmap}
  alias Botyaga.Pnmap.Absorb
  alias Botyaga.Ubl.Parser

  def import(company_id, params) do
    filename = or_default(str(params, "filename"), "invoice.xml")
    direction = params |> str("direction") |> String.trim()
    direction = if direction == "", do: "in", else: direction

    cond do
      direction not in ["in", "out"] ->
        {:error, {422, "direction must be 'in' or 'out'"}}

      true ->
        with {:ok, xml} <- decode_xml(str(params, "xml"), str(params, "content_base64")),
             {:ok, doc} <- parse(xml) do
          preview(company_id, doc, filename, direction)
        end
    end
  end

  defp parse(xml) do
    case Parser.parse(xml) do
      {:ok, doc} -> {:ok, doc}
      {:error, msg} -> {:error, {422, msg}}
    end
  end

  defp preview(company_id, doc, filename, direction) do
    {cvat, ceik} = company_ids(company_id)
    vat_registered = Pnmap.company_vat_registered(company_id)
    {party, direction} = choose(doc, direction, cvat, ceik)
    hit = Pnmap.counterpart_hit(company_id, party.vat, party.eik)

    lines = Enum.map(doc.lines, fn line -> line_item(company_id, hit, line) end)

    {lines, tot_net, tot_vat, tot_all, vatex} =
      totals(lines, doc, direction, vat_registered)

    original_id = Pnmap.invoice_by_number(company_id, doc.original)

    out = %{
      direction: direction,
      filename: filename,
      vat_registered: vat_registered,
      invoice_number: doc.number,
      issue_date: doc.issue_date,
      due_date: doc.due_date,
      tax_event_date: if(doc.tax_point == "", do: doc.issue_date, else: doc.tax_point),
      document_type: Parser.document_type(doc.root, doc.type_code),
      counterpart_name: party.name,
      counterpart_eik: party.eik,
      counterpart_vat_number: party.vat,
      currency: if(doc.currency == "", do: "EUR", else: doc.currency),
      currency_rate: if(doc.currency_rate == "", do: "1", else: doc.currency_rate),
      payment_method: Parser.pay_method(doc.pay_code),
      payment_note: doc.note,
      vat_exemption_reason: vatex,
      original_invoice_number: doc.original,
      total_net_amount: tot_net,
      total_vat_amount: tot_vat,
      total_amount: tot_all,
      lines: lines
    }

    out = if original_id > 0, do: Map.put(out, :original_invoice_id, original_id), else: out

    out =
      if hit do
        out
        |> Map.put(:counterpart_id, hit.id)
        |> Map.put(:counterpart, %{id: hit.id, name: hit.name, eik: hit.eik, vat_number: hit.vat})
      else
        out
      end

    {:ok, out}
  end

  defp line_item(company_id, hit, line) do
    pid = if hit, do: Pnmap.product_for(company_id, hit.id, line.name, line.seller), else: 0
    pid = if pid == 0, do: Pnmap.product_by_code(company_id, line.seller), else: pid

    item = %{
      "description" => line.name,
      "seller_code" => line.seller,
      "quantity" => if(line.qty == "", do: "1", else: line.qty),
      "unit" => if(line.unit == "", do: "C62", else: line.unit),
      "unit_price" => if(line.price == "", do: "0", else: line.price),
      "vat_rate" => if(line.pct == "", do: "20", else: line.pct),
      "net_amount" => line.net,
      "vat_amount" => "",
      "total_amount" => ""
    }

    if pid > 0, do: Map.put(item, "product_id", pid), else: item
  end

  defp totals(lines, doc, direction, vat_registered) do
    vatex = Parser.exemption(doc.exemption, doc.tax_cat)

    if vat_registered do
      {lines, doc.net, doc.vat, doc.total, vatex}
    else
      {lines, tot_net, tot_vat, tot_all} =
        if direction == "in" do
          {lines, net, all} = Absorb.absorb(lines, doc.net, doc.vat, doc.total)
          {lines, net, "0.00", all}
        else
          lines =
            Enum.map(lines, fn line ->
              line
              |> Map.put("vat_rate", "0")
              |> Map.put("vat_amount", "0.00")
              |> Map.put("total_amount", Map.get(line, "net_amount"))
            end)

          {lines, doc.net, "0.00", doc.net}
        end

      vatex = if String.trim(vatex) == "", do: "VATEX-EU-SM", else: vatex
      {lines, tot_net, tot_vat, tot_all, vatex}
    end
  end

  defp choose(doc, direction, vat, eik) do
    sup = is_us?(doc.supplier, vat, eik)
    cus = is_us?(doc.customer, vat, eik)

    cond do
      sup and not cus -> {doc.customer, "out"}
      cus and not sup -> {doc.supplier, "in"}
      direction == "out" -> {doc.customer, "out"}
      true -> {doc.supplier, direction}
    end
  end

  defp is_us?(party, vat, eik) do
    same?(party.vat, vat) or same?(party.eik, eik) or
      same?(party.eik, digits(vat)) or same?(eik, digits(party.vat))
  end

  defp same?(a, b) do
    x = a |> String.trim() |> String.downcase()
    y = b |> String.trim() |> String.downcase()
    x != "" and x == y
  end

  defp digits(raw), do: String.replace(raw || "", ~r/[^0-9]/, "")

  defp company_ids(company_id) do
    case Companies.get_company(company_id) do
      nil -> {"", ""}
      c -> {c.vat_number || "", c.eik || ""}
    end
  end

  defp decode_xml(raw, b64) do
    xml = raw |> String.trim() |> String.trim_leading("\uFEFF")

    xml =
      if xml == "" do
        if String.trim(b64) == "" do
          {:error, {422, "празен файл"}}
        else
          case Base.decode64(clean_b64(b64)) do
            :error ->
              {:error, {422, "Файлът не е XML."}}

            {:ok, bytes} ->
              if byte_size(bytes) > 8_000_000 do
                {:error, {422, "Файлът е над 8 МБ."}}
              else
                bytes |> String.trim_leading("\uFEFF") |> String.trim()
              end
          end
        end
      else
        xml
      end

    case xml do
      {:error, _} = error -> error
      xml when byte_size(xml) > 8_000_000 -> {:error, {422, "Файлът е над 8 МБ."}}
      xml -> {:ok, xml}
    end
  end

  defp clean_b64(raw) do
    head = String.slice(raw, 0, 80)

    body =
      if String.contains?(head, "base64") do
        case :binary.match(raw, ",") do
          {pos, _} -> binary_part(raw, pos + 1, byte_size(raw) - pos - 1)
          :nomatch -> raw
        end
      else
        raw
      end

    String.replace(body, ~r/\s/, "")
  end

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end

  defp or_default(value, fallback) do
    if String.trim(value) == "", do: fallback, else: value
  end
end

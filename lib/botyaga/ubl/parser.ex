defmodule Botyaga.Ubl.Parser do
  @moduledoc """
  UBL 2.1 / Peppol BIS → полета за чернова. Без база. Ръчен streaming парсер
  (стек от отворени тагове), порт на `ubl_xml.rs`.
  """

  def parse(xml) do
    if not String.contains?(xml, "<") do
      {:error, "Файлът не е XML."}
    else
      state = %{draft: empty_draft(), line: empty_line(), stack: []}
      state = scan(xml, state)

      if state.draft.root == "",
        do: {:error, "Файлът не е UBL фактура."},
        else: {:ok, state.draft}
    end
  end

  defp empty_draft do
    %{
      root: "",
      number: "",
      issue_date: "",
      due_date: "",
      tax_point: "",
      type_code: "",
      currency: "",
      currency_rate: "",
      pay_code: "",
      note: "",
      net: "",
      vat: "",
      total: "",
      tax_cat: "",
      exemption: "",
      original: "",
      supplier: empty_party(),
      customer: empty_party(),
      lines: []
    }
  end

  defp empty_party, do: %{name: "", eik: "", vat: "", country: ""}
  defp empty_line, do: %{qty: "", unit: "C62", net: "", name: "", seller: "", price: "", pct: ""}

  defp scan(<<>>, state), do: state

  defp scan(rest, state) do
    if String.starts_with?(rest, "<"), do: tag(rest, state), else: text(rest, state)
  end

  defp text(rest, state) do
    {raw, rest2} = split_at(rest, "<")
    value = text_of(raw)
    state = if value == "", do: state, else: apply_text(state, value)
    scan(rest2, state)
  end

  defp tag(rest, state) do
    cond do
      String.starts_with?(rest, "</") ->
        case :binary.match(rest, ">") do
          :nomatch ->
            state

          {pos, _} ->
            name = local(binary_part(rest, 2, pos - 2))
            state = state |> close_line(name) |> pop_stack(name)
            scan(drop(rest, pos + 1), state)
        end

      String.starts_with?(rest, "<?") or String.starts_with?(rest, "<!") ->
        case :binary.match(rest, ">") do
          :nomatch -> state
          {pos, _} -> scan(drop(rest, pos + 1), state)
        end

      true ->
        case :binary.match(rest, ">") do
          :nomatch ->
            state

          {pos, _} ->
            body = binary_part(rest, 1, pos - 1)
            closed = String.ends_with?(body, "/")
            tag_text = body |> String.trim_trailing("/") |> String.trim()
            name = local(tag_text)
            state = put_root(state, name)
            state = if closed, do: state, else: push_stack(state, name, tag_text)
            scan(drop(rest, pos + 1), state)
        end
    end
  end

  defp split_at(bin, needle) do
    case :binary.match(bin, needle) do
      :nomatch -> {bin, <<>>}
      {pos, _} -> {binary_part(bin, 0, pos), drop(bin, pos)}
    end
  end

  defp drop(bin, n), do: binary_part(bin, n, byte_size(bin) - n)

  defp put_root(state, name) do
    if state.draft.root == "" and name in ["Invoice", "CreditNote", "DebitNote"],
      do: %{state | draft: %{state.draft | root: name}},
      else: state
  end

  defp push_stack(state, name, tag_text) do
    unit =
      if name in ["InvoicedQuantity", "CreditedQuantity"],
        do: attr(tag_text, "unitCode"),
        else: ""

    %{state | stack: [%{name: name, unit: unit} | state.stack]}
  end

  defp pop_stack(state, name) do
    case state.stack do
      [%{name: ^name} | rest] -> %{state | stack: rest}
      _ -> state
    end
  end

  defp close_line(state, name) do
    if name in ["InvoiceLine", "CreditNoteLine"] do
      line = state.line

      draft =
        if line.name != "" or line.net != "" do
          pushed = %{line | qty: if(line.qty == "", do: "1", else: line.qty)}
          %{state.draft | lines: state.draft.lines ++ [pushed]}
        else
          state.draft
        end

      %{state | draft: draft, line: empty_line()}
    else
      state
    end
  end

  defp local(tag) do
    head = tag |> String.split(~r/\s+/, trim: true) |> List.first() || tag
    head |> String.split(":") |> List.last() || head
  end

  defp attr(tag, key) do
    needle = "#{key}=\""

    case :binary.match(tag, needle) do
      :nomatch ->
        ""

      {pos, _} ->
        rest = drop(tag, pos + byte_size(needle))
        {value, _} = split_at(rest, "\"")
        value
    end
  end

  defp text_of(raw), do: raw |> String.split(~r/\s+/, trim: true) |> Enum.join(" ")
  defp dot(raw), do: raw |> text_of() |> String.replace(",", ".")
  defp date(raw), do: raw |> text_of() |> String.slice(0, 10)

  defp apply_text(state, value) do
    case state.stack do
      [] ->
        state

      [cur | _] ->
        parent = state.stack |> Enum.at(1) |> Map.get(:name, "")
        tag = cur.name

        cond do
          in_line?(state.stack) -> line_text(state, tag, parent, cur, value)
          party_key(state.stack) != nil -> party_text(state, tag, parent, value)
          true -> root_text(state, tag, parent, value)
        end
    end
  end

  defp in_line?(stack), do: Enum.any?(stack, &(&1.name in ["InvoiceLine", "CreditNoteLine"]))

  defp party_key(stack) do
    cond do
      Enum.any?(stack, &(&1.name == "AccountingSupplierParty")) -> :supplier
      Enum.any?(stack, &(&1.name == "AccountingCustomerParty")) -> :customer
      true -> nil
    end
  end

  defp line_text(state, tag, parent, cur, value) do
    line = state.line

    line =
      cond do
        tag in ["InvoicedQuantity", "CreditedQuantity"] ->
          unit = if cur.unit != "", do: cur.unit, else: line.unit
          %{line | qty: dot(value), unit: unit}

        tag == "LineExtensionAmount" ->
          %{line | net: dot(value)}

        tag == "Name" and parent == "Item" ->
          %{line | name: value}

        tag == "Description" and parent == "Item" and line.name == "" ->
          %{line | name: value}

        tag == "ID" and parent == "SellersItemIdentification" ->
          %{line | seller: value}

        tag == "PriceAmount" ->
          %{line | price: dot(value)}

        tag == "Percent" and parent == "ClassifiedTaxCategory" ->
          %{line | pct: dot(value)}

        true ->
          line
      end

    %{state | line: line}
  end

  defp party_text(state, tag, parent, value) do
    key = party_key(state.stack)
    p = Map.get(state.draft, key)

    p =
      cond do
        tag == "Name" and parent == "PartyName" and p.name == "" -> %{p | name: value}
        tag == "RegistrationName" and p.name == "" -> %{p | name: value}
        tag == "CompanyID" and parent == "PartyTaxScheme" -> %{p | vat: value}
        tag == "EndpointID" and p.vat == "" -> %{p | vat: value}
        tag == "ID" and parent == "PartyIdentification" -> %{p | eik: value}
        tag == "CompanyID" and parent == "PartyLegalEntity" and p.eik == "" -> %{p | eik: value}
        tag == "IdentificationCode" and parent == "Country" -> %{p | country: value}
        true -> p
      end

    %{state | draft: Map.put(state.draft, key, p)}
  end

  defp root_text(state, tag, parent, value) do
    d = state.draft
    root_parent = parent in ["Invoice", "CreditNote", "DebitNote"]

    d =
      cond do
        tag == "ID" and root_parent ->
          %{d | number: value}

        tag == "IssueDate" and root_parent ->
          %{d | issue_date: date(value)}

        tag == "DueDate" and root_parent ->
          %{d | due_date: date(value)}

        tag == "TaxPointDate" and root_parent ->
          %{d | tax_point: date(value)}

        tag in ["InvoiceTypeCode", "CreditNoteTypeCode"] ->
          %{d | type_code: value}

        tag == "DocumentCurrencyCode" ->
          %{d | currency: value}

        tag == "PaymentMeansCode" ->
          %{d | pay_code: value}

        tag == "Note" and parent == "PaymentTerms" ->
          %{d | note: value}

        tag == "ID" and parent == "InvoiceDocumentReference" ->
          %{d | original: value}

        tag == "TaxAmount" and parent == "TaxTotal" and d.vat == "" ->
          %{d | vat: dot(value)}

        tag == "LineExtensionAmount" and parent == "LegalMonetaryTotal" ->
          %{d | net: dot(value)}

        tag == "TaxExclusiveAmount" and d.net == "" ->
          %{d | net: dot(value)}

        tag == "PayableAmount" ->
          %{d | total: dot(value)}

        tag == "TaxInclusiveAmount" and d.total == "" ->
          %{d | total: dot(value)}

        tag == "CalculationRate" and d.currency_rate == "" ->
          %{d | currency_rate: dot(value)}

        tag == "ID" and parent == "TaxCategory" and (d.tax_cat == "" or value != "S") ->
          %{d | tax_cat: value}

        tag == "TaxExemptionReasonCode" ->
          %{d | exemption: value}

        true ->
          d
      end

    %{state | draft: d}
  end

  def document_type(root, code) do
    code = String.trim(code || "")

    cond do
      root == "CreditNote" or code in ["381", "396"] -> "03"
      root == "DebitNote" or code == "383" -> "02"
      code == "325" -> "proforma"
      true -> "01"
    end
  end

  def pay_method(code) do
    case String.trim(code || "") do
      c when c in ["10", "20"] -> "в брой"
      c when c in ["48", "54", "55"] -> "карта"
      "97" -> "компенсация"
      _ -> "банков превод"
    end
  end

  def exemption(raw, category) do
    code = raw |> String.trim() |> String.upcase()

    if code != "" do
      code
    else
      case String.trim(category || "") do
        "AE" -> "VATEX-EU-AE"
        "G" -> "VATEX-EU-G"
        "K" -> "VATEX-EU-IC"
        "O" -> "VATEX-EU-O"
        _ -> ""
      end
    end
  end
end

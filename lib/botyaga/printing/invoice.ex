defmodule Botyaga.Printing.Invoice do
  @moduledoc """
  Block-ове за печат на фактура. Получател и доставчик се разменят при входяща.
  Порт на `invoice_print.rs#blocks`.
  """

  alias Botyaga.Dec
  alias Botyaga.Printing
  alias Botyaga.Printing.{Load, Words}
  alias Botyaga.Vat

  def build(company_id, id, format, copy) do
    with {:ok, fmt} <- Printing.check_format(format),
         {:ok, doc} <- Load.load(company_id, id),
         {:ok, bytes} <- Printing.render(blocks(doc, copy), fmt) do
      filename = Printing.download_name(doc.inv.number, doc.inv.document_type, fmt)
      {:ok, %{bytes: bytes, filename: filename, format: fmt}}
    end
  end

  def blocks(doc, copy) do
    inv = doc.inv
    outgoing = inv.direction != "in"
    company = Load.party(doc.company)
    counterpart = Load.party(doc.counterpart)

    counterpart =
      if counterpart.name == "",
        do: %{counterpart | name: inv.counterpart_name || ""},
        else: counterpart

    recipient = if outgoing, do: counterpart, else: company
    supplier = if outgoing, do: company, else: counterpart
    currency = or_trim(inv.currency, "EUR")
    number = "#{Printing.doc_prefix(inv.document_type)}#{inv.number}"

    out = []
    out = if inv.status == "cancelled", do: out ++ [{:line, "АНУЛИРАНА"}], else: out

    head_title =
      if inv.document_type == "09" and String.trim(inv.vat_article || "") != "",
        do: "ПРОТОКОЛ ПО #{String.upcase(String.trim(inv.vat_article))} ОТ ЗДДС",
        else: Printing.doc_title(inv.document_type)

    label = if copy, do: "КОПИЕ", else: "ОРИГИНАЛ"
    out = out ++ [{:head, head_title}, {:line, "( #{label} )"}, {:line, "№ #{number}"}]

    out =
      if String.trim(doc.original_number) != "",
        do:
          out ++
            [
              {:line,
               "Към документ № #{doc.original_number} / #{Printing.bg_date(doc.original_date)}"}
            ],
        else: out

    out =
      if String.trim(inv.issue_date || "") != "",
        do: out ++ [{:line, "Дата: #{Printing.bg_date(inv.issue_date)}"}],
        else: out

    out =
      if String.trim(inv.tax_event_date || "") != "",
        do: out ++ [{:line, "Дан. дата: #{Printing.bg_date(inv.tax_event_date)}"}],
        else: out

    out =
      out ++
        [
          {:table, parties(recipient, supplier)},
          {:table, lines(doc)},
          {:totals, totals(inv, currency)}
        ]

    method = String.trim(inv.payment_method || "")
    bank_payment = method == "банков превод" or inv.bank_account_id > 0
    bank_name = or_trim(doc.bank[:name], "")
    bank_iban = or_trim(doc.bank[:iban], company.iban)
    bank_bic = or_trim(doc.bank[:bic], company.bic)

    out =
      if bank_payment do
        out ++ [{:line, "Начин: По банкова сметка"}]
      else
        if method != "", do: out ++ [{:line, "Начин на плащане: #{method}"}], else: out
      end

    out =
      if String.trim(inv.due_date || "") != "",
        do: out ++ [{:line, "Срок: #{Printing.bg_date(inv.due_date)}"}],
        else: out

    out =
      if bank_payment do
        bank_lines =
          [
            {"Банка: #{bank_name}", bank_name != ""},
            {"IBAN: #{bank_iban}", bank_iban != ""},
            {"BIC: #{bank_bic}", bank_bic != ""}
          ]
          |> Enum.filter(&elem(&1, 1))
          |> Enum.map(&{:line, elem(&1, 0)})

        out ++ bank_lines
      else
        out
      end

    out =
      if String.trim(inv.notes || "") != "",
        do: out ++ [{:line, "Забележка: #{String.trim(inv.notes)}"}],
        else: out

    out =
      if String.trim(inv.vat_exemption_reason || "") != "",
        do:
          out ++
            [
              {:line,
               "Основание за неначисляване на ДДС: #{Vat.Ex.print_label(String.trim(inv.vat_exemption_reason))}"}
            ],
        else: out

    total = Dec.money(Dec.or0(inv.total_amount))
    out = out ++ [{:line, "Словом: #{Words.words(total, currency)}"}]
    out ++ [{:table, signatures(recipient, supplier)}]
  end

  defp signatures(rec, sup) do
    received = if rec.contact != "", do: rec.contact <> " ", else: ""
    prepared = if sup.mol != "", do: sup.mol <> " ", else: ""

    [
      [
        "Получил: #{received}____________________",
        "Съставил: #{prepared}____________________"
      ]
    ]
  end

  defp parties(rec, sup) do
    sup_vat = "ДДС №: #{sup.vat}"
    sup_vat = if sup.mol != "", do: sup_vat <> " · МОЛ: " <> sup.mol, else: sup_vat

    rows = [
      ["ПОЛУЧАТЕЛ", "ДОСТАВЧИК"],
      [rec.name, sup.name],
      [place(rec.address, rec.city), place(sup.address, sup.city)],
      ["ЕИК: #{rec.eik}", "ЕИК: #{sup.eik}"],
      ["ДДС №: #{rec.vat}", sup_vat]
    ]

    if rec.contact != "", do: rows ++ [["Лице за контакт: #{rec.contact}", ""]], else: rows
  end

  defp lines(doc) do
    header = ["No", "Стока / услуга", "К-во", "Мярка", "Ед. цена", "ДДС%", "Общо"]

    rows =
      doc.lines
      |> Enum.with_index()
      |> Enum.map(fn {line, i} ->
        [
          Integer.to_string(i + 1),
          line.description || "",
          line.quantity || "",
          unit_display(line.unit || ""),
          Dec.money(Dec.or0(line.unit_price)),
          line.vat_rate || "",
          Dec.money(Dec.or0(line.net_amount))
        ]
      end)

    [header | rows]
  end

  defp totals(inv, currency) do
    rows = []

    rows =
      if inv.document_type == "07" and String.trim(inv.customs_statistical || "") != "" do
        rows ++
          [
            [
              "Статистическа стойност",
              "#{Dec.money(Dec.or0(inv.customs_statistical))} #{currency}"
            ],
            ["Мито", "#{Dec.money(Dec.or0(inv.customs_duty))} #{currency}"]
          ]
      else
        rows
      end

    rows = rows ++ [["Данъчна основа", "#{Dec.money(Dec.or0(inv.net_amount))} #{currency}"]]
    rows = rows ++ [["ДДС", "#{Dec.money(Dec.or0(inv.vat_amount))} #{currency}"]]

    rows =
      if Dec.or0(inv.discount_amount) > 0,
        do: rows ++ [["Отстъпка", "#{Dec.money(Dec.or0(inv.discount_amount))} #{currency}"]],
        else: rows

    rows ++ [["ОБЩО ЗА ПЛАЩАНЕ", "#{Dec.money(Dec.or0(inv.total_amount))} #{currency}"]]
  end

  defp place(address, city) do
    case {address == "", city == ""} do
      {true, true} -> ""
      {false, true} -> address
      {true, false} -> city
      {false, false} -> "#{address} #{city}"
    end
  end

  defp or_trim(value, fallback) do
    t = String.trim(value || "")
    if t == "", do: fallback, else: t
  end

  def unit_display(code) do
    case String.trim(code || "") do
      u when u in ["", "C62", "EA", "PCE", "H87", "E48", "NAR"] -> "бр."
      "SET" -> "к-т"
      "PR" -> "чифт"
      "DZN" -> "дуз."
      "GRO" -> "грос"
      "MIL" -> "хил."
      "CEN" -> "стотици"
      "KGM" -> "кг"
      "GRM" -> "г"
      "MGM" -> "мг"
      "TNE" -> "т"
      "DTN" -> "дт"
      "LBR" -> "lb"
      "ONZ" -> "oz"
      "CTM" -> "ct"
      "MTR" -> "м"
      "CMT" -> "см"
      "MMT" -> "мм"
      "KMT" -> "км"
      "DMT" -> "дм"
      "INH" -> "in"
      "FOT" -> "ft"
      "YRD" -> "yd"
      "NMI" -> "nmi"
      "MTK" -> "м²"
      "CMK" -> "см²"
      "MMK" -> "мм²"
      u when u in ["LTR", "LT"] -> "л"
      "MLT" -> "мл"
      "HLT" -> "хл"
      "HUR" -> "час"
      "DAY" -> "ден"
      "MON" -> "месец"
      "WEE" -> "седм."
      "PK" -> "пакет"
      other -> other
    end
  end
end

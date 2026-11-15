defmodule Botyaga.Saft.GL do
  @moduledoc """
  Сметкоплан и дневник за месечния SAF-T. AccountID е код на НАП, TaxpayerAccountID
  е номерът във фирмата. Контрагентът е на записа. Порт на `saft_gl.rs`.
  """

  alias Botyaga.Dec
  alias Botyaga.Saft.Xml

  def accounts_xml(s, year, month) do
    w = Xml.window(year, month, s.company.fys)
    map = balances(s, w)

    body =
      Enum.map_join(s.accounts, fn a ->
        od = get(map, "a:#{a.id}:od")
        oc = get(map, "a:#{a.id}:oc")
        pd = get(map, "a:#{a.id}:pd")
        pc = get(map, "a:#{a.id}:pc")
        desc = or_clip(a.name, 256, a.nra)

        Xml.open("Account") <>
          Xml.text("AccountID", a.nra) <>
          Xml.text("AccountDescription", desc) <>
          Xml.text("TaxpayerAccountID", a.firm) <>
          Xml.text("AccountType", "Bifunctional") <>
          Xml.bal("OpeningDebitBalance", "OpeningCreditBalance", od, oc) <>
          Xml.bal("ClosingDebitBalance", "ClosingCreditBalance", od + pd, oc + pc) <>
          Xml.close("Account")
      end)

    Xml.open("GeneralLedgerAccounts") <> body <> Xml.close("GeneralLedgerAccounts")
  end

  def entries_xml(s, year, month) do
    w = Xml.window(year, month, s.company.fys)
    cur = currency(s)

    {body, n, debit, credit} =
      Enum.reduce(s.entries, {"", 0, 0, 0}, fn e, {body, n, debit, credit} ->
        if not Xml.same_co(e.company_id, s.company_id) or
             not String.starts_with?(e.date, w.prefix) do
          {body, n, debit, credit}
        else
          day = String.slice(e.date, 0, 10)

          if String.length(day) < 10 do
            {body, n, debit, credit}
          else
            case tx(s, e, day, year, month, cur) do
              nil -> {body, n, debit, credit}
              {xml, d, c} -> {body <> xml, n + 1, debit + d, credit + c}
            end
          end
        end
      end)

    if body == "" do
      ""
    else
      Xml.open("GeneralLedgerEntries") <>
        Xml.text("NumberOfEntries", Integer.to_string(n)) <>
        Xml.text("TotalDebit", Dec.money(debit)) <>
        Xml.text("TotalCredit", Dec.money(credit)) <>
        Xml.open("Journal") <>
        Xml.text("JournalID", "GL") <>
        Xml.text("Description", "Счетоводни записи") <>
        Xml.text("Type", "GLEntry") <>
        body <>
        Xml.close("Journal") <>
        Xml.close("GeneralLedgerEntries")
    end
  end

  defp tx(s, e, day, year, month, cur) do
    case Map.get(s.lines, e.id) do
      nil ->
        nil

      lines ->
        desc = or_clip(e.description, 256, "Запис")

        {body, n, debit, credit, tx_c, tx_s} =
          Enum.reduce(lines, {"", 0, 0, 0, "0", "0"}, fn line, {body, n, d, c, tc, ts} ->
            case Enum.find(s.accounts, &(&1.id == line.account_id)) do
              nil ->
                {body, n, d, c, tc, ts}

              acc ->
                {d, c} =
                  if line.direction == "debit",
                    do: {d + line.amount, c},
                    else: {d, c + line.amount}

                {cust, supp} =
                  if Xml.pref(acc.nra, "411") or Xml.pref(acc.nra, "401"),
                    do: who(s, e.counterpart_id, line.direction),
                    else: {"0", "0"}

                tc = if cust != "0", do: cust, else: tc
                ts = if supp != "0", do: supp, else: ts

                amount_xml =
                  if line.direction == "debit",
                    do: Xml.amount("DebitAmount", line.amount, cur),
                    else: Xml.amount("CreditAmount", line.amount, cur)

                line_xml =
                  Xml.open("TransactionLine") <>
                    Xml.text("RecordID", Integer.to_string(line.id)) <>
                    Xml.text("AccountID", acc.nra) <>
                    Xml.text("TaxpayerAccountID", acc.firm) <>
                    Xml.text("CustomerID", cust) <>
                    Xml.text("SupplierID", supp) <>
                    Xml.text("Description", desc) <>
                    amount_xml <>
                    tax_info(line, cur) <>
                    Xml.close("TransactionLine")

                {body <> line_xml, n + 1, d, c, tc, ts}
            end
          end)

        if n == 0 do
          nil
        else
          xml =
            Xml.open("Transaction") <>
              Xml.text("TransactionID", Integer.to_string(e.id)) <>
              Xml.text("Period", Integer.to_string(month)) <>
              Xml.text("PeriodYear", Integer.to_string(year)) <>
              Xml.text("TransactionDate", day) <>
              Xml.text("TransactionType", "Normal") <>
              Xml.text("Description", desc) <>
              Xml.text("SystemEntryDate", day) <>
              Xml.text("GLPostingDate", day) <>
              Xml.text("CustomerID", tx_c) <>
              Xml.text("SupplierID", tx_s) <>
              body <>
              Xml.close("Transaction")

          {xml, debit, credit}
        end
    end
  end

  defp tax_info(line, cur) do
    {type, code, vat} =
      if line.vat != 0, do: {"100", "100211", line.vat}, else: {"000", "000000", 0}

    Xml.open("TaxInformation") <>
      Xml.text("TaxType", type) <>
      Xml.text("TaxCode", code) <>
      Xml.amount("TaxAmount", vat, cur) <>
      Xml.close("TaxInformation")
  end

  @doc "Клиент само на дебит при двойна роля. Иначе по вида на контрагента."
  def who(s, counterpart_id, direction) do
    case Enum.find(s.parties, &(&1.id == counterpart_id)) do
      nil ->
        {"0", "0"}

      p ->
        eik = or_clip(p.eik, 35, "0")
        {client, supplier} = roles(p.kind)

        cond do
          client and not supplier -> {eik, "0"}
          supplier and not client -> {"0", eik}
          client and supplier -> if direction == "debit", do: {eik, "0"}, else: {"0", eik}
          true -> {"0", "0"}
        end
    end
  end

  def roles(kind) do
    case String.trim(kind || "") do
      k when k in ["customer", "client"] -> {true, false}
      "supplier" -> {false, true}
      "both" -> {true, true}
      _ -> {false, false}
    end
  end

  def balances(s, w) do
    fy = w.fy_start |> String.slice(0, 4) |> String.to_integer()

    map =
      Enum.reduce(s.openings, %{}, fn o, map ->
        if o.year != fy or not Map.has_key?(s.nra, o.account_id) do
          map
        else
          map =
            map
            |> add("a:#{o.account_id}:od", o.debit)
            |> add("a:#{o.account_id}:oc", o.credit)

          if o.counterpart_id > 0 do
            map
            |> add_party(s, o.account_id, o.counterpart_id, "o", "debit", o.debit)
            |> add_party(s, o.account_id, o.counterpart_id, "o", "credit", o.credit)
          else
            map
          end
        end
      end)

    Enum.reduce(s.entries, map, fn e, map ->
      if not Xml.same_co(e.company_id, s.company_id) do
        map
      else
        case Xml.bucket(e.date, w) do
          nil ->
            map

          kind ->
            lines = Map.get(s.lines, e.id, [])
            slot = if kind == :o, do: "o", else: "p"

            Enum.reduce(lines, map, fn line, map ->
              if not Map.has_key?(s.nra, line.account_id) do
                map
              else
                side = if line.direction == "debit", do: "d", else: "c"
                map = add(map, "a:#{line.account_id}:#{slot}#{side}", line.amount)

                if e.counterpart_id > 0,
                  do:
                    add_party(
                      map,
                      s,
                      line.account_id,
                      e.counterpart_id,
                      slot,
                      line.direction,
                      line.amount
                    ),
                  else: map
              end
            end)
        end
      end
    end)
  end

  defp add_party(map, s, account_id, counterpart_id, slot, direction, amount) do
    case Map.get(s.nra, account_id) do
      nil ->
        map

      code ->
        side = if direction == "debit", do: "d", else: "c"

        map =
          if Xml.pref(code, "411"),
            do: add(map, "p:#{counterpart_id}:c:#{slot}#{side}", amount),
            else: map

        if Xml.pref(code, "401"),
          do: add(map, "p:#{counterpart_id}:s:#{slot}#{side}", amount),
          else: map
    end
  end

  defp add(map, _key, 0), do: map
  defp add(map, key, amount), do: Map.update(map, key, amount, &(&1 + amount))

  def get(map, key), do: Map.get(map, key, 0)

  def currency(s) do
    c = String.trim(s.company.currency || "")
    if c == "", do: "EUR", else: c
  end

  defp or_clip(value, n, fallback) do
    d = Xml.clip(value, n)
    if d == "", do: fallback, else: d
  end
end

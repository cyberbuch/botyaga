defmodule Botyaga.Banking.Xml do
  @moduledoc "XML банкови извлечения: Postbank, UniCredit, OBB, ISO camt.053."

  alias Botyaga.Banking.Csv

  defp xml_unescape(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  def xml_tag(block, name) do
    close = "</#{name}>"

    case :binary.match(block, close) do
      :nomatch ->
        ""

      {end_pos, _} ->
        head = binary_part(block, 0, end_pos)
        open = "<#{name}"

        case last_index(head, open) do
          nil ->
            ""

          pos ->
            after_open =
              binary_part(head, pos + byte_size(open), byte_size(head) - pos - byte_size(open))

            if String.starts_with?(after_open, " nil=\"true\"") or
                 String.starts_with?(after_open, "/") do
              ""
            else
              case :binary.match(after_open, ">") do
                :nomatch ->
                  ""

                {gt, _} ->
                  after_open
                  |> binary_part(gt + 1, byte_size(after_open) - gt - 1)
                  |> String.trim()
                  |> xml_unescape()
              end
            end
        end
    end
  end

  defp last_index(head, open) do
    case :binary.matches(head, open) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  def xml_attr(block, name, attr) do
    open = "<#{name}"

    case :binary.match(block, open) do
      :nomatch ->
        ""

      {pos, _} ->
        rest = binary_part(block, pos + byte_size(open), byte_size(block) - pos - byte_size(open))

        case :binary.match(rest, ">") do
          :nomatch ->
            ""

          {gt, _} ->
            tag_head = binary_part(rest, 0, gt)
            needle = "#{attr}=\""

            case :binary.match(tag_head, needle) do
              :nomatch ->
                ""

              {apos, _} ->
                val =
                  binary_part(
                    tag_head,
                    apos + byte_size(needle),
                    byte_size(tag_head) - apos - byte_size(needle)
                  )

                case :binary.match(val, "\"") do
                  :nomatch -> ""
                  {i, _} -> binary_part(val, 0, i)
                end
            end
        end
    end
  end

  def xml_blocks(xml, name) do
    open = "<#{name}"
    close = "</#{name}>"
    collect_blocks(xml, open, close, [])
  end

  defp collect_blocks(cur, open, close, acc) do
    case :binary.match(cur, open) do
      :nomatch ->
        Enum.reverse(acc)

      {s, _} ->
        rest = binary_part(cur, s + byte_size(open), byte_size(cur) - s - byte_size(open))

        ok =
          String.starts_with?(rest, ">") or String.starts_with?(rest, " ") or
            String.starts_with?(rest, "\t") or String.starts_with?(rest, "\r") or
            String.starts_with?(rest, "\n")

        if not ok do
          collect_blocks(rest, open, close, acc)
        else
          case :binary.match(rest, ">") do
            :nomatch ->
              Enum.reverse(acc)

            {gt, _} ->
              body = binary_part(rest, gt + 1, byte_size(rest) - gt - 1)

              case :binary.match(body, close) do
                :nomatch ->
                  Enum.reverse(acc)

                {e, _} ->
                  block = binary_part(body, 0, e)

                  remaining =
                    binary_part(
                      body,
                      e + byte_size(close),
                      byte_size(body) - e - byte_size(close)
                    )

                  collect_blocks(remaining, open, close, [block | acc])
              end
          end
        end
    end
  end

  defp join_desc(parts) do
    parts |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" — ")
  end

  defp first_block(xml, name), do: xml |> xml_blocks(name) |> List.first() || ""

  ## PostBank XML

  def parse_postbank_xml(content) do
    {iban, currency, txs} =
      content
      |> xml_blocks("AccountTransactionsHistoryModel")
      |> Enum.reduce({"", "", []}, fn b, {iban, currency, txs} ->
        acc_iban = xml_tag(b, "AccountNumber")
        iban = if iban == "" and acc_iban != "", do: acc_iban, else: iban
        local = first_block(b, "AmountLocalCurrency")
        tx_block = first_block(b, "TransactionAmount")
        {raw_val, cur} = {xml_tag(local, "Value"), xml_tag(local, "Currency")}

        {raw_val, cur} =
          if raw_val == "" or Csv.norm_money(raw_val) == "0.00" do
            {xml_tag(tx_block, "Value"), xml_tag(tx_block, "Currency")}
          else
            {raw_val, cur}
          end

        currency = if currency == "" and cur != "", do: cur, else: currency
        amt = Csv.norm_money(raw_val)

        if amt in ["", "0.00"] do
          {iban, currency, txs}
        else
          dir = xml_tag(b, "FlowDirection")

          amount =
            if String.downcase(dir) in ["outbound", "debit"],
              do: "-" <> String.trim_leading(amt, "-"),
              else: String.trim_leading(amt, "-")

          date = Csv.flex_date(xml_tag(b, "BookingDate"))
          date = if date == "", do: Csv.flex_date(xml_tag(b, "ValueDate")), else: date

          if date == "" do
            {iban, currency, txs}
          else
            rem = xml_tag(b, "RemittanceInformation")
            description = if rem != "", do: rem, else: xml_tag(b, "TransactionType")

            tx = %{
              date: date,
              amount: amount,
              currency: if(cur == "", do: "EUR", else: cur),
              description: description,
              contra_name: xml_tag(b, "CorrespondentName"),
              contra_iban: xml_tag(b, "CorrespondentAccount"),
              reference: xml_tag(b, "BorderNumber"),
              is_duplicate: false
            }

            {iban, currency, txs ++ [tx]}
          end
        end
      end)

    %{
      format_name: "PostBank XML",
      account_iban: iban,
      account_currency: if(currency == "", do: "EUR", else: currency),
      txs: txs
    }
  end

  ## UniCredit XML

  def parse_unicredit_xml(content) do
    {iban, currency, txs} =
      content
      |> xml_blocks("AccountMovement")
      |> Enum.reduce({"", "", []}, fn b, {iban, currency, txs} ->
        acc = first_block(b, "Account")
        acc_iban = xml_tag(acc, "IBAN")
        acc_ccy = xml_tag(acc, "CCY")
        iban = if iban == "" and acc_iban != "", do: acc_iban, else: iban
        currency = if currency == "" and acc_ccy != "", do: acc_ccy, else: currency
        amt = Csv.norm_money(xml_tag(b, "Amount"))

        if amt in ["", "0.00"] do
          {iban, currency, txs}
        else
          mtype = xml_tag(b, "MovementType")

          amount =
            if String.downcase(mtype) == "debit",
              do: "-" <> String.trim_leading(amt, "-"),
              else: String.trim_leading(amt, "-")

          date = Csv.flex_date(xml_tag(b, "PaymentDate"))
          date = if date == "", do: Csv.flex_date(xml_tag(b, "ValueDate")), else: date

          if date == "" do
            {iban, currency, txs}
          else
            ccy = xml_tag(b, "CCY")

            description =
              join_desc([
                xml_tag(b, "Reason"),
                xml_tag(b, "NarrativeI02"),
                xml_tag(b, "Narrative")
              ])

            tx = %{
              date: date,
              amount: amount,
              currency: if(ccy == "", do: currency, else: ccy),
              description: description,
              contra_name: xml_tag(b, "OppositeSideName"),
              contra_iban: xml_tag(b, "OppositeSideAccount"),
              reference: xml_tag(b, "DocumentReference"),
              is_duplicate: false
            }

            {iban, currency, txs ++ [tx]}
          end
        end
      end)

    %{
      format_name: "UniCredit XML",
      account_iban: iban,
      account_currency: if(currency == "", do: "EUR", else: currency),
      txs: txs
    }
  end

  ## OBB XML

  def parse_obb_xml(content) do
    iban = xml_tag(content, "IBAN_S")
    currency = xml_tag(content, "CURRENCY")
    currency = if currency == "", do: "EUR", else: currency

    blocks =
      cond do
        (b = xml_blocks(content, "TRANSACTION")) != [] -> b
        (b = xml_blocks(content, "ROW")) != [] -> b
        (b = xml_blocks(content, "RECORD")) != [] -> b
        String.contains?(content, "<POST_DATE>") -> [content]
        true -> []
      end

    txs =
      Enum.reduce(blocks, [], fn b, acc ->
        date = Csv.flex_date(xml_tag(b, "POST_DATE"))

        if date == "" do
          acc
        else
          d = Csv.norm_money(xml_tag(b, "AMOUNT_D"))
          c = Csv.norm_money(xml_tag(b, "AMOUNT_C"))

          amount =
            cond do
              c not in ["", "0.00"] -> String.trim_leading(c, "-")
              d not in ["", "0.00"] -> "-" <> String.trim_leading(d, "-")
              true -> nil
            end

          if amount do
            description =
              join_desc([xml_tag(b, "REM_I"), xml_tag(b, "REM_II"), xml_tag(b, "TR_NAME")])

            acc ++
              [
                %{
                  date: date,
                  amount: amount,
                  currency: currency,
                  description: description,
                  contra_name: xml_tag(b, "NAME_R"),
                  contra_iban: xml_tag(b, "IBAN_R"),
                  reference: xml_tag(b, "REFERENCE"),
                  is_duplicate: false
                }
              ]
          else
            acc
          end
        end
      end)

    %{format_name: "OBB XML", account_iban: iban, account_currency: currency, txs: txs}
  end

  ## ISO camt.053

  def parse_camt053(content) do
    acct = first_block(content, "Acct")
    iban = xml_tag(acct, "IBAN")
    currency = xml_tag(acct, "Ccy")

    {currency, txs} =
      content
      |> xml_blocks("Ntry")
      |> Enum.reduce({currency, []}, fn ntry, {currency, txs} ->
        amt = Csv.norm_money(xml_tag(ntry, "Amt"))

        if amt in ["", "0.00"] do
          {currency, txs}
        else
          ccy = xml_attr(ntry, "Amt", "Ccy")
          ccy = if ccy == "", do: currency, else: ccy
          currency = if currency == "" and ccy != "", do: ccy, else: currency
          ind = xml_tag(ntry, "CdtDbtInd")
          is_debit = String.downcase(ind) in ["dbit", "d"]

          amount =
            if is_debit,
              do: "-" <> String.trim_leading(amt, "-"),
              else: String.trim_leading(amt, "-")

          book = first_block(ntry, "BookgDt")
          book = if book == "", do: ntry, else: book
          val = first_block(ntry, "ValDt")
          val = if val == "", do: ntry, else: val
          date = Csv.flex_date(xml_tag(book, "Dt"))
          date = if date == "", do: Csv.flex_date(xml_tag(book, "DtTm")), else: date
          date = if date == "", do: Csv.flex_date(xml_tag(val, "Dt")), else: date

          if date == "" do
            {currency, txs}
          else
            reference = xml_tag(ntry, "AcctSvcrRef")
            reference = if reference == "", do: xml_tag(ntry, "EndToEndId"), else: reference
            reference = if reference == "NOTPROVIDED", do: "", else: reference
            description = join_desc([xml_tag(ntry, "Ustrd"), xml_tag(ntry, "AddtlNtryInf")])
            {contra_name, contra_iban} = camt_parties(ntry, is_debit)

            tx = %{
              date: date,
              amount: amount,
              currency: if(ccy == "", do: "EUR", else: ccy),
              description: description,
              contra_name: contra_name,
              contra_iban: contra_iban,
              reference: reference,
              is_duplicate: false
            }

            {currency, txs ++ [tx]}
          end
        end
      end)

    %{
      format_name: "ISO camt.053",
      account_iban: iban,
      account_currency: if(currency == "", do: "EUR", else: currency),
      txs: txs
    }
  end

  defp camt_parties(ntry, is_debit) do
    case first_block(ntry, "RltdPties") do
      "" ->
        {"", ""}

      rltd ->
        party_tag = if is_debit, do: "Cdtr", else: "Dbtr"
        acct_tag = if is_debit, do: "CdtrAcct", else: "DbtrAcct"
        name = rltd |> first_block(party_tag) |> xml_tag("Nm")
        iban = rltd |> first_block(acct_tag) |> xml_tag("IBAN")
        {name, iban}
    end
  end
end

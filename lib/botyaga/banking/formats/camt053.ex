defmodule Botyaga.Banking.Formats.Camt053 do
  @moduledoc "ISO 20022 camt.053 банкови извлечения."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv
  import Botyaga.Banking.Xml

  @impl true
  def key, do: "camt053"

  @impl true
  def name, do: "ISO camt.053"

  @impl true
  def matches?(content) do
    String.contains?(content, "BkToCstmrStmt") or String.contains?(content, "<Ntry>") or
      String.contains?(content, ":Ntry>")
  end

  @impl true
  def parse(content) do
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

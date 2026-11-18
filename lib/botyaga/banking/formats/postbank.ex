defmodule Botyaga.Banking.Formats.Postbank do
  @moduledoc "PostBank XML банкови извлечения."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv
  import Botyaga.Banking.Xml

  @impl true
  def key, do: "postbank_xml"

  @impl true
  def name, do: "PostBank XML"

  @impl true
  def matches?(content), do: String.contains?(content, "<AccountTransactionsHistory")

  @impl true
  def parse(content) do
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
end

defmodule Botyaga.Banking.Formats.UniCredit do
  @moduledoc "UniCredit XML банкови извлечения."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv
  import Botyaga.Banking.Xml

  @impl true
  def key, do: "unicredit_xml"

  @impl true
  def name, do: "UniCredit XML"

  @impl true
  def matches?(content), do: String.contains?(content, "<AccountMovement>")

  @impl true
  def parse(content) do
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
end

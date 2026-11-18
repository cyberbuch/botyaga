defmodule Botyaga.Banking.Formats.Obb do
  @moduledoc "OBB XML банкови извлечения."

  @behaviour Botyaga.Banking.Format

  alias Botyaga.Banking.Csv
  import Botyaga.Banking.Xml

  @impl true
  def key, do: "obb_xml"

  @impl true
  def name, do: "OBB XML"

  @impl true
  def matches?(content) do
    String.contains?(content, "<IBAN_S>") or String.contains?(content, "<POST_DATE>")
  end

  @impl true
  def parse(content) do
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
end

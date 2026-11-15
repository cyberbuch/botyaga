defmodule Botyaga.Saft.Annual do
  @moduledoc "Годишен SAF-T: активи, оценки и придобивания за годината. Порт на `saft_annual.rs`."

  alias Botyaga.Dec
  alias Botyaga.Saft.Xml

  def annual_xml(s, year) do
    y = Integer.to_string(year)

    {assets, tx, n} =
      Enum.reduce(s.assets, {"", "", 0}, fn a, {assets, tx, n} ->
        if not Xml.same_co(a.company_id, s.company_id) or String.length(a.acquired) < 10 do
          {assets, tx, n}
        else
          day = String.slice(a.acquired, 0, 10)
          start = if String.length(a.startup) >= 10, do: String.slice(a.startup, 0, 10), else: day
          asset_id = or_clip(a.inventory, 35, "FA-#{a.id}")
          assets = assets <> asset_block(a, asset_id, day, start)

          if String.starts_with?(day, y),
            do: {assets, tx <> asset_tx(asset_id, day, a.cost), n + 1},
            else: {assets, tx, n}
        end
      end)

    source =
      if tx == "",
        do: "",
        else:
          Xml.open("AssetTransactions") <>
            Xml.text("NumberOfAssetTransactions", Integer.to_string(n)) <>
            tx <>
            Xml.close("AssetTransactions")

    Xml.open("MasterFilesAnnual") <>
      Xml.open("Assets") <>
      assets <>
      Xml.close("Assets") <>
      Xml.close("MasterFilesAnnual") <>
      Xml.open("SourceDocumentsAnnual") <> source <> Xml.close("SourceDocumentsAnnual")
  end

  defp asset_block(a, asset_id, day, start) do
    desc = or_clip(a.name, 256, asset_id)

    Xml.open("Asset") <>
      Xml.text("AssetID", asset_id) <>
      Xml.text("AccountID", "204") <>
      Xml.text("Description", desc) <>
      Xml.open("AssetSupplier") <>
      Xml.text("SupplierName", "Неизвестен") <>
      Xml.text("SupplierID", "0") <>
      Xml.address("PostalAddress", %{
        street: "",
        number: "",
        extra: "",
        building: "",
        city: "",
        post: "",
        region: "",
        country: "BG",
        kind: ""
      }) <>
      Xml.close("AssetSupplier") <>
      Xml.text("DateOfAcquisition", day) <>
      Xml.text("StartUpDate", start) <>
      Xml.open("Valuations") <>
      valuation(a) <>
      dap(a) <>
      Xml.close("Valuations") <>
      Xml.close("Asset")
  end

  defp valuation(a) do
    book = a.cost - a.acc

    Xml.open("ValuationSAP") <>
      Xml.text("ValuationClass", "Счетоводен") <>
      Xml.text("AcquisitionAndProductionCostsBegin", Dec.money(a.cost)) <>
      Xml.text("AcquisitionAndProductionCostsEnd", Dec.money(a.cost)) <>
      Xml.text("InvestmentSupport", "0.00") <>
      Xml.text("AssetLifeMonth", Xml.or_text(a.life, "0")) <>
      Xml.text("AssetAddition", "0.00") <>
      Xml.text("Transfers", "0.00") <>
      Xml.text("AssetDisposal", "0.00") <>
      Xml.text("BookValueBegin", Dec.money(book)) <>
      Xml.text("DepreciationMethod", Xml.clip(Xml.or_text(a.method, "linear"), 35)) <>
      Xml.text("DepreciationPercentage", Xml.or_text(a.rate, "0")) <>
      Xml.text("DepreciationForPeriod", "0.00") <>
      Xml.text("AppreciationForPeriod", "0.00") <>
      Xml.open("ExtraordinaryDepreciationsForPeriod") <>
      Xml.open("ExtraordinaryDepreciationForPeriod") <>
      Xml.text("ExtraordinaryDepreciationMethod", "0") <>
      Xml.text("ExtraordinaryDepreciationAmountForPeriod", "0.00") <>
      Xml.close("ExtraordinaryDepreciationForPeriod") <>
      Xml.close("ExtraordinaryDepreciationsForPeriod") <>
      Xml.text("AccumulatedDepreciation", Dec.money(a.acc)) <>
      Xml.text("BookValueEnd", Dec.money(book)) <>
      Xml.close("ValuationSAP")
  end

  defp dap(a) do
    tax_value = a.cost - a.tax_acc

    Xml.open("ValuationDAP") <>
      Xml.text("ValuationClass", "Данъчен") <>
      Xml.text(
        "CategoryTaxDepreciable",
        Xml.clip(Xml.or_text(Integer.to_string(a.category_id), "0"), 35)
      ) <>
      Xml.text("TaxDepreciableValue", Dec.money(a.cost)) <>
      Xml.text("AccruedTaxDepreciation", Dec.money(a.tax_acc)) <>
      Xml.text("TaxValueAsset", Dec.money(tax_value)) <>
      Xml.text("AnnualTaxDepreciationRate", Xml.or_text(a.tax_rate, "0")) <>
      Xml.text("MonthChangeAssetValue", "0") <>
      Xml.text("MonthSuspensionResumptionAccrual", "0") <>
      Xml.text("MonthWriteOffAccounting", "0") <>
      Xml.text("MonthWriteOffTax", "0") <>
      Xml.text("NumberMonthsDepreciationDuring", "0") <>
      Xml.text("DepreciationForPeriod", "0.00") <>
      Xml.text("AccumulatedDepreciation", Dec.money(a.tax_acc)) <>
      Xml.text("TaxValueEndPeriod", Dec.money(tax_value)) <>
      Xml.close("ValuationDAP")
  end

  defp asset_tx(asset_id, day, cost) do
    id = Xml.clip("ACQ-#{asset_id}", 70)

    Xml.open("AssetTransaction") <>
      Xml.text("AssetTransactionID", id) <>
      Xml.text("AssetID", asset_id) <>
      Xml.text("AssetTransactionType", "10") <>
      Xml.text("Description", "Придобиване") <>
      Xml.text("AssetTransactionDate", day) <>
      Xml.text("TransactionID", id) <>
      Xml.open("AssetTransactionValuations") <>
      Xml.open("AssetTransactionValuation") <>
      Xml.text("AcquisitionAndProductionCostsOnTransaction", Dec.money(cost)) <>
      Xml.text("BookValueOnTransaction", Dec.money(cost)) <>
      Xml.text("AssetTransactionAmount", Dec.money(cost)) <>
      Xml.close("AssetTransactionValuation") <>
      Xml.close("AssetTransactionValuations") <>
      Xml.close("AssetTransaction")
  end

  defp or_clip(value, n, fallback) do
    c = Xml.clip(value, n)
    if c == "", do: fallback, else: c
  end
end

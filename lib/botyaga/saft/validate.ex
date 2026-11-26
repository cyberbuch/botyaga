defmodule Botyaga.Saft.Validate do
  @moduledoc """
  Проверка на генерирания SAF-T XML според BG_SAFT_Schema V1.0.1 (secret/SAFT_BG)
  и основни счетоводни инварианти. Връща списъци `errors` и `warnings`, без да
  спира експорта — целта е файлът да се извежда, но проблемите да са видими.

  XSD-правилата, които хващаме: SourceDocumentsMonthly винаги съдържа подредени
  SalesInvoices → Payments → PurchaseInvoices, като всяка секция изисква поне
  един запис; броят в NumberOfEntries трябва да съвпада с реалните записи;
  GeneralLedgerEntries трябва да е балансиран.
  """

  alias Botyaga.Dec

  @sections ~w(SalesInvoices Payments PurchaseInvoices)

  def validate(xml, snap, mode) do
    errors = []
    warnings = []

    errors = header_checks(xml, errors)

    {errors, warnings} =
      case mode do
        "monthly" ->
          {e, w} = master_files_checks(xml, errors)
          {e, w} = source_documents_checks(xml, e, w)
          {ledger_entries_checks(xml, e), w}

        "annual" ->
          {master_annual_checks(xml, errors), warnings}

        "ondemand" ->
          {ondemand_checks(xml, errors), warnings}

        _ ->
          {errors, warnings}
      end

    warnings = content_warnings(xml, snap, warnings)

    %{
      errors: Enum.reverse(errors),
      warnings: Enum.reverse(warnings),
      valid: errors == [],
      counts: counts(xml),
      mode: mode
    }
  end

  ## Заглавка

  defp header_checks(xml, errors) do
    required = [
      {"AuditFileVersion", "версия на файла"},
      {"AuditFileCountry", "държава"},
      {"AuditFileDateCreated", "дата на създаване"},
      {"SoftwareCompanyName", "име на софтуера"},
      {"SoftwareID", "идентификатор на софтуера"},
      {"DefaultCurrencyCode", "валута по подразбиране"}
    ]

    Enum.reduce(required, errors, fn {tag, what}, acc ->
      case text(xml, tag) do
        nil -> [error("header.#{tag}", "липсва #{what} (#{tag})") | acc]
        "" -> [error("header.#{tag}", "празно поле #{what} (#{tag})") | acc]
        _ -> acc
      end
    end)
  end

  ## Master files

  defp master_files_checks(xml, errors) do
    acc =
      cond do
        not has?(xml, "GeneralLedgerAccounts") ->
          [error("master.accounts", "липсва GeneralLedgerAccounts") | errors]

        count(xml, "Account") == 0 ->
          [error("master.accounts", "GeneralLedgerAccounts е празен — липсват сметки") | errors]

        true ->
          errors
      end

    {acc, parties_warnings(xml)}
  end

  # Липсата на контрагенти е предупреждение, не грешка.
  defp parties_warnings(xml) do
    if count(xml, "Customer") == 0 and count(xml, "Supplier") == 0 do
      [warn("master.parties", "няма контрагенти (Customers/Suppliers) в MasterFiles")]
    else
      []
    end
  end

  ## Изходни документи: подредба, присъствие, бройки, празни секции

  defp source_documents_checks(xml, errors, warnings) do
    positions = Enum.map(@sections, fn s -> {s, index_of(xml, s)} end)

    missing = Enum.filter(positions, fn {_s, i} -> is_nil(i) end)

    errors =
      Enum.reduce(missing, errors, fn {s, _}, acc ->
        [error("source.missing", "липсва задължителната секция #{s}") | acc]
      end)

    present_idx =
      positions
      |> Enum.reject(fn {_s, i} -> is_nil(i) end)
      |> Enum.map(fn {_s, i} -> i end)

    ordered? = Enum.sort(present_idx) == present_idx

    errors =
      if not ordered? do
        [
          error(
            "source.order",
            "секциите SalesInvoices → Payments → PurchaseInvoices са в грешен ред"
          )
          | errors
        ]
      else
        errors
      end

    Enum.reduce(@sections, {errors, warnings}, fn s, {acc, warn} ->
      case text(section(xml, s), "NumberOfEntries") do
        nil ->
          {[error("source.#{s}.count", "секция #{s} няма NumberOfEntries") | acc], warn}

        raw ->
          declared = int_or(raw, -1)
          actual = section_records(xml, s)

          acc =
            if declared != actual do
              [
                error(
                  "source.#{s}.count",
                  "секция #{s}: NumberOfEntries = #{declared}, а записите са #{actual}"
                )
                | acc
              ]
            else
              acc
            end

          acc =
            if actual == 0 do
              [error("source.#{s}.empty", "#{s} е празна — XSD изисква поне един запис") | acc]
            else
              acc
            end

          {acc, warn}
      end
    end)
  end

  ## Годишен режим: МДА

  defp master_annual_checks(xml, errors) do
    acc =
      if has?(xml, "MasterFilesAnnual"),
        do: errors,
        else: [error("master.annual", "липсва MasterFilesAnnual") | errors]

    acc =
      if has?(xml, "SourceDocumentsAnnual") do
        n = count(section(xml, "SourceDocumentsAnnual"), "AssetTransaction")

        if n == 0,
          do: [
            error(
              "annual.transactions.empty",
              "SourceDocumentsAnnual е празна — липсват движения по активи"
            )
            | acc
          ],
          else: acc
      else
        [error("annual.missing", "липсва SourceDocumentsAnnual") | acc]
      end

    assets = count(xml, "Asset")

    if assets == 0,
      do: [warn("annual.assets", "няма активи (Assets) в годишния файл") | acc],
      else: acc
  end

  ## Режим при поискване: движения на стоки

  defp ondemand_checks(xml, errors) do
    acc =
      if has?(xml, "MasterFilesOnDemand"),
        do: errors,
        else: [error("master.ondemand", "липсва MasterFilesOnDemand") | errors]

    acc =
      if has?(xml, "SourceDocumentsOnDemand") do
        n = count(section(xml, "SourceDocumentsOnDemand"), "StockMovement")

        if n == 0,
          do: [
            error(
              "ondemand.moves.empty",
              "SourceDocumentsOnDemand е празна — липсват движения на стоки"
            )
            | acc
          ],
          else: acc
      else
        [error("ondemand.missing", "липсва SourceDocumentsOnDemand") | acc]
      end

    acc
  end

  ## Дневник

  # Месечният файл винаги носи GeneralLedgerEntries: едно Journal с N транзакции.
  defp ledger_entries_checks(xml, errors) do
    if not has?(xml, "GeneralLedgerEntries") do
      [
        error("ledger.entries", "липсва GeneralLedgerEntries (задължителна за месечен файл)")
        | errors
      ]
    else
      errors = check_ledger_count(xml, errors)
      check_ledger_balance(xml, errors)
    end
  end

  defp check_ledger_count(xml, errors) do
    declared = int_or(text(xml, "NumberOfEntries") || "", -1)
    actual = count(xml, "Transaction")

    if declared != actual do
      [
        error(
          "ledger.count",
          "GeneralLedgerEntries: NumberOfEntries = #{declared}, а транзакциите са #{actual}"
        )
        | errors
      ]
    else
      errors
    end
  end

  defp check_ledger_balance(xml, errors) do
    td = Float.parse(text(xml, "TotalDebit") || "") |> to_float()
    tc = Float.parse(text(xml, "TotalCredit") || "") |> to_float()

    cond do
      is_nil(td) or is_nil(tc) ->
        [error("ledger.totals", "GeneralLedgerEntries няма TotalDebit/TotalCredit") | errors]

      abs(td - tc) > 0.005 ->
        [
          error(
            "ledger.balance",
            "GeneralLedgerEntries не е балансиран: дебит #{td} ≠ кредит #{tc}"
          )
          | errors
        ]

      true ->
        errors
    end
  end

  defp to_float({v, _}), do: v
  defp to_float(:error), do: nil

  ## Предупреждения за съдържание

  defp content_warnings(_xml, nil, warnings), do: warnings

  defp content_warnings(xml, snap, warnings) do
    c = snap.company

    w =
      []
      |> add(if blank?(c.city), do: warn("company.city", "липсва град в адреса на фирмата"))
      |> add(if blank?(c.post), do: warn("company.post", "липсва пощенски код"))
      |> add(if blank?(c.mol), do: warn("company.mol", "липсва МОЛ (контактно лице)"))
      |> add(if blank?(c.phone), do: warn("company.phone", "липсва телефон за контакт"))
      |> add(if blank?(c.email), do: warn("company.email", "липсва имейл за контакт"))
      |> add(if blank?(c.vat), do: warn("company.vat", "липсва ДДС номер"))
      |> add(
        if Enum.empty?(snap.bank_accounts),
          do: warn("company.bank", "няма банкови сметки в заглавката")
      )
      |> add(
        if Enum.empty?(snap.owners),
          do: warn("ownership", "няма бенефицирани собственици (Ownership)")
      )
      |> add(
        if has?(xml, "AuditFileRegion") == false,
          do: warn("company.region", "областта на фирмата е непозната (без AuditFileRegion)")
      )

    w ++ warnings
  end

  ## Брояч

  defp counts(xml) do
    %{
      accounts: count(xml, "Account"),
      customers: count(xml, "Customer"),
      suppliers: count(xml, "Supplier"),
      sales_invoices: section_records(xml, "SalesInvoices"),
      purchase_invoices: section_records(xml, "PurchaseInvoices"),
      payments: section_records(xml, "Payments"),
      transactions: count(xml, "Transaction")
    }
  end

  ## Помощници за разбор на нашия XML

  defp error(code, msg), do: %{severity: :error, code: code, message: msg}
  defp warn(code, msg), do: %{severity: :warning, code: code, message: msg}

  defp open_re(name), do: ~r/<nsSAFT:#{name}(?:\s[^>]*?)?\/?>/

  defp has?(xml, name), do: Regex.match?(open_re(name), xml)

  defp count(xml, name), do: Regex.scan(open_re(name), xml) |> length()

  defp index_of(xml, name) do
    case Regex.run(open_re(name), xml, return: :index) do
      [{i, _}] -> i
      _ -> nil
    end
  end

  @doc "Съдържание на елемент (първо срещане, без вложени)."
  def text(xml, name) do
    case Regex.run(~r/<nsSAFT:#{name}(?:\s[^>]*)?>(.*?)<\/nsSAFT:#{name}>/s, xml) do
      [_, inner] -> inner
      _ -> nil
    end
  end

  @doc "Субстринг на секция между отварящия и затварящия ѝ таг."
  def section(xml, name) do
    case Regex.run(~r/<nsSAFT:#{name}(?:\s[^>]*)?>(.*?)<\/nsSAFT:#{name}>/s, xml) do
      [_, inner] -> inner
      _ -> ""
    end
  end

  defp section_records(xml, "SalesInvoices"), do: count(section(xml, "SalesInvoices"), "Invoice")

  defp section_records(xml, "PurchaseInvoices"),
    do: count(section(xml, "PurchaseInvoices"), "Invoice")

  defp section_records(xml, "Payments"), do: count(section(xml, "Payments"), "Payment")

  defp section_records(xml, "MovementOfGoods"),
    do: count(section(xml, "MovementOfGoods"), "MovementOfGood")

  defp section_records(_xml, _), do: 0

  defp int_or("", d), do: d

  defp int_or(raw, _default) do
    case Integer.parse(raw) do
      {n, _} -> n
      :error -> -1
    end
  end

  defp blank?(nil), do: true
  defp blank?(s), do: String.trim(s) == ""

  defp add(list, item) when is_nil(item), do: list
  defp add(list, item), do: [item | list]

  @doc "Сума от XML-суми (за бъдещи проверки)."
  def money_sum(vals), do: Enum.reduce(vals, 0, &(&2 + Dec.or0(&1)))
end

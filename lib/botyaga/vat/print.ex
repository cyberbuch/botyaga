defmodule Botyaga.Vat.Print do
  @moduledoc """
  Печат на ДДС дневниците (покупки/продажби) за собственика и проверка:
  PDF (Chromium sidecar, landscape), XLSX и ODS.

  Дневниците имат много колони и не се събират на лист по ширина — затова
  колоните, в които няма нито един ненулев запис (само за сумовите колони),
  и текстовите колони без никакво съдържание (стока/услуга, код доставка),
  се пропускат. Първите колони (№, клон, вид, документ, дата, ДДС №,
  контрагент) винаги остават.
  """

  alias Botyaga.Invoicing.Money
  alias Botyaga.Printing
  alias Botyaga.Printing.Sheet

  # _landscape_style за широките дневници: PDF на A4 landscape с по-дребен шрифт.
  @wide_style """
  @page { size: A4 landscape; margin: 12mm 10mm; }
  table { font-size: 8pt; }
  th, td { padding: 2pt 3pt; }
  """

  # {json ключ, заглавие, :text | :amount}
  @purchase_cols [
    {:row, "№", :text},
    {:branch, "Клон", :text},
    {:document_type, "Вид", :text},
    {:document_number, "Документ №", :text},
    {:document_date, "Дата", :text},
    {:counterpart_vat_number, "ДДС № на контрагента", :text},
    {:counterpart_name, "Контрагент", :text},
    {:goods, "Вид стока/услуга", :text},
    {:base_no_credit, "ДО без ДК", :amount},
    {:base_full_credit, "ДО пълен ДК", :amount},
    {:vat_full_credit, "ДДС пълен ДК", :amount},
    {:base_partial, "ДО частичен ДК", :amount},
    {:vat_partial, "ДДС частичен ДК", :amount},
    {:annual_adj, "Годишна корекция", :amount},
    {:vop_base, "ВОП (покупки)", :amount},
    {:delivery_code, "Код доставка", :text}
  ]

  @sales_cols [
    {:row, "№", :text},
    {:branch, "Клон", :text},
    {:document_type, "Вид", :text},
    {:document_number, "Документ №", :text},
    {:document_date, "Дата", :text},
    {:counterpart_vat_number, "ДДС № на контрагента", :text},
    {:counterpart_name, "Контрагент", :text},
    {:goods, "Вид стока/услуга", :text},
    {:total_base, "Общо ДО", :amount},
    {:total_vat, "Общо ДДС", :amount},
    {:base_20, "ДО 20%", :amount},
    {:vat_20, "ДДС 20%", :amount},
    {:vop_sales_base, "ВОП продажби ДО", :amount},
    {:vop_sales_vat, "ВОП продажби ДДС", :amount},
    {:base_82, "ДО чл. 82", :amount},
    {:pers_amount, "Данък за лични нужди", :amount},
    {:base_9, "ДО 9%", :amount},
    {:vat_9, "ДДС 9%", :amount},
    {:base_0, "ДО 0%", :amount},
    {:base_vod, "ВОД", :amount},
    {:base_art, "ДО чл. 173", :amount},
    {:base_services, "Услуги чл. 21, ал. 2", :amount},
    {:base_69, "ДО чл. 69", :amount},
    {:base_exempt, "Освободени", :amount},
    {:base_tri, "Тристранни сделки", :amount},
    {:delivery_code, "Код доставка", :text}
  ]

  @always_text [
    :row,
    :branch,
    :document_type,
    :document_number,
    :document_date,
    :counterpart_vat_number,
    :counterpart_name
  ]

  def register_of(raw) do
    if to_string(raw || "") in ["sales", "prodagbi", "prodajbi"], do: "sales", else: "purchases"
  end

  def title(register),
    do: if(register == "sales", do: "Дневник за продажби", else: "Дневник за покупки")

  def slug(register), do: if(register == "sales", do: "dnevnik-prodagbi", else: "dnevnik-pokupki")

  @doc "Мрежа за печат: ред-заглавка, редовете, ред „Общо“. Празните колони се пропускат."
  def grid(body, register) do
    cols = if register == "sales", do: @sales_cols, else: @purchase_cols
    rows = Map.get(body, if(register == "sales", do: :sales, else: :purchases)) || []
    kept = Enum.filter(cols, &keep_col?(&1, rows))

    header = Enum.map(kept, fn {_k, label, _kind} -> label end)

    data =
      Enum.map(rows, fn r ->
        Enum.map(kept, fn {k, _label, kind} -> cell(r, k, kind) end)
      end)

    totals =
      Enum.map(kept, fn {k, _label, kind} ->
        case kind do
          :amount ->
            sum =
              Enum.reduce(rows, 0, fn r, acc -> acc + (Money.cents(Map.get(r, k) || "0") || 0) end)

            Money.money(sum)

          :text ->
            if k == :row, do: "Общо", else: ""
        end
      end)

    [header | data ++ [totals]]
  end

  defp keep_col?({key, _label, :amount}, rows) do
    Enum.any?(rows, fn r -> (Money.cents(Map.get(r, key) || "0") || 0) != 0 end)
  end

  defp keep_col?({key, _label, :text}, rows) do
    if key in @always_text do
      true
    else
      Enum.any?(rows, fn r -> String.trim(to_string(Map.get(r, key) || "")) != "" end)
    end
  end

  defp cell(row, key, :amount) do
    Money.money(Money.cents(Map.get(row, key) || "0") || 0)
  end

  defp cell(row, :document_date, :text) do
    Printing.bg_date(to_string(Map.get(row, :document_date) || ""))
  end

  defp cell(row, key, :text), do: to_string(Map.get(row, key) || "")

  @doc "Същата мрежа, но сумите са в български формат (1 200,00) — за PDF."
  def display_grid(grid) do
    Enum.map(grid, fn row ->
      Enum.map(row, fn c ->
        case Sheet.number(c) do
          nil -> c
          num -> num.bg_text
        end
      end)
    end)
  end

  @doc "PDF през sidecar-а: landscape, дребен шрифт, bg числа."
  def pdf(body, register) do
    rows = Map.get(body, if(register == "sales", do: :sales, else: :purchases)) || []

    blocks = [
      {:head, "#{title(register)} — #{body.period}"},
      {:line, "#{body.company_name} · #{body.company_vat}"},
      {:line, "Записи: #{length(rows)}"},
      {:line, ""},
      {:table, display_grid(grid(body, register))}
    ]

    Printing.render(blocks, "pdf", @wide_style)
  end

  @doc "XLSX/ODS от мрежата; bg=true показва числата в български формат."
  def sheet(body, register, format, bg) do
    g = grid(body, register)

    case format do
      "xlsx" ->
        {:ok, Sheet.xlsx(g, bg),
         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}

      "ods" ->
        {:ok, Sheet.ods(g, bg), "application/vnd.oasis.opendocument.spreadsheet"}

      _ ->
        {:error, {400, "format трябва да е xlsx или ods"}}
    end
  end
end

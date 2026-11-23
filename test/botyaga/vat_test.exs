defmodule Botyaga.VatTest do
  use ExUnit.Case, async: true

  alias Botyaga.Vat.{Files, Fmt, Line, Print}
  alias Botyaga.Invoicing.Money

  describe "Fmt" do
    test "период във формите YYYY-MM и YYYYMM" do
      assert {:ok, %{iso: "2026-10", nap: "202610"}} = Fmt.parse_period("202610")
      assert {:ok, %{iso: "2026-10"}} = Fmt.parse_period("2026-10")
      assert {:error, :empty} = Fmt.parse_period("")
      assert {:error, :format} = Fmt.parse_period("2026-13")
      assert {:error, :format} = Fmt.parse_period("2026/10")
    end

    test "кирилица в Windows-1251" do
      assert Fmt.cp1251("Бага") == <<0xC1, 0xE0, 0xE3, 0xE0>>
      assert Fmt.cp1251("A") == "A"
    end

    test "идентификация на контрагент" do
      assert Fmt.cp_ident("BG123456789", "123456789") == "BG123456789"
      assert Fmt.cp_ident("", "201559838") == "201559838"
      assert Fmt.cp_ident("", "999999999") == "999999999"
      assert Fmt.cp_ident("", "") == "999999999"
    end

    test "вид документ и ставки" do
      assert Fmt.doc_type("invoice") == "01"
      assert Fmt.doc_type("credit_note") == "03"
      assert Fmt.doc_type("1") == "01"
      assert Fmt.doc_type("03") == "03"
      assert Fmt.rate_kind("9") == "9"
      assert Fmt.rate_kind("0") == "0"
      assert Fmt.rate_kind("20") == "20"
      assert Fmt.is_credit_doc("03")
      assert Fmt.sales_excluded("11")
      assert Fmt.purch_excluded("05")
    end
  end

  describe "Line и Cells" do
    test "демо месец: дължим ДДС" do
      cells = Line.cells()
      sale = Line.from_totals("sales", 100_000, 20_000) |> Map.put(:doc_type, "01")
      buy = Line.from_totals("purchase", 25_000, 5_000) |> Map.put(:doc_type, "01")
      cells = cells |> Line.cells_add(sale) |> Line.cells_add(buy) |> Line.cells_finish()

      assert Money.money(cells.s11) == "1000.00"
      assert Money.money(cells.s21) == "200.00"
      assert Money.money(cells.p31) == "250.00"
      assert Money.money(cells.p41) == "50.00"
      assert Money.money(cells.r50) == "150.00"
      assert cells.r60 == 0
    end

    test "кредитното обръща знака само веднъж" do
      ln = Line.from_totals("sales", 5_000, 1_000) |> Map.put(:doc_type, "03")
      ln = Line.apply_credit(ln)
      assert ln.s_tb == -5_000
      ln = Line.apply_credit(ln)
      assert ln.s_tb == -5_000
    end

    test "нулева ставка ВОД" do
      ln = Line.empty("sales") |> Line.add_sale(8_000, 0, "0", "VATEX-EU-IC")
      assert ln.s_vod == 8_000
      assert ln.s_tv == 0
    end

    test "протокол 117 влиза в двата дневника и се нулира" do
      cells = Line.cells()

      s_proto =
        Line.empty("sales") |> Map.put(:doc_type, "09") |> Line.add_vop_sale(50_000, 10_000)

      p_proto =
        Line.empty("purchase") |> Map.put(:doc_type, "09") |> Line.add_purch(50_000, 10_000)

      cells = cells |> Line.cells_add(s_proto) |> Line.cells_add(p_proto) |> Line.cells_finish()

      assert Money.money(cells.s12) == "500.00"
      assert Money.money(cells.s22) == "100.00"
      assert Money.money(cells.p31) == "500.00"
      assert Money.money(cells.p41) == "100.00"
      assert cells.r50 == 0
      assert cells.r60 == 0
    end
  end

  describe "Files" do
    test "подаващ ДДС данните по избор на фирмата" do
      assert Files.submitter(
               "manager",
               "111",
               "Счетоводител",
               "222",
               "Пълномощник",
               "333",
               "Управител"
             ) ==
               "333/Управител"

      assert Files.submitter(
               "authorized",
               "111",
               "Счетоводител",
               "222",
               "Пълномощник",
               "333",
               "Управител"
             ) ==
               "222/Пълномощник"

      assert Files.submitter(
               "accountant",
               "111",
               "Счетоводител",
               "222",
               "Пълномощник",
               "333",
               "Управител"
             ) ==
               "111/Счетоводител"

      # Липсват данни за избраното — се влиза на първото налично.
      assert Files.submitter("authorized", "111", "Счетоводител", "", "", "333", "Управител") ==
               "111/Счетоводител"

      assert Files.declarant(
               "manager",
               "111",
               "Счетоводител",
               "222",
               "Пълномощник",
               "333",
               "Управител"
             ) ==
               {"333", "Управител", "R"}

      # Счетоводителят е пълномощник за ДДС.
      assert Files.declarant(
               "accountant",
               "111",
               "Счетоводител",
               "222",
               "Пълномощник",
               "333",
               "Управител"
             ) ==
               {"111", "Счетоводител", "A"}
    end

    test "фиксирана ширина" do
      ln = Line.empty("purchase")
      assert byte_size(Files.pok_line("BG1", "202610", "", 1, ln)) == 276
      sale = Line.empty("sales")
      assert byte_size(Files.pro_line("BG1", "202610", "", 1, sale)) == 426
      assert byte_size(Files.deklar("BG1", "Бага", "202610", "Иван", Line.cells())) == 592
    end

    test "ZIP без компресия се отваря" do
      z = Files.zip3("a", "b", "c")
      assert binary_part(z, 0, 4) == "PK\x03\x04"
      assert :binary.match(z, "PK\x05\x06") != :nomatch
    end
  end

  describe "Print (печат на дневниците)" do
    defp purchase_row(overrides) do
      %{
        row: 1,
        branch: "0",
        document_type: "01",
        document_number: "0001",
        document_date: "2026-11-03",
        counterpart_vat_number: "BG222333444",
        counterpart_name: "Доставчик ООД",
        goods: "Стока",
        delivery_code: "",
        base_no_credit: "0.00",
        base_full_credit: "0.00",
        vat_full_credit: "0.00",
        base_partial: "0.00",
        vat_partial: "0.00",
        annual_adj: "0.00",
        vop_base: "0.00"
      }
      |> Map.merge(overrides)
    end

    test "празните сумови колони се пропускат, празният текстов колон също" do
      body = %{
        period: "2026-11",
        company_name: "Тест ООД",
        company_vat: "BG207123456",
        purchases: [purchase_row(%{base_full_credit: "100.00", vat_full_credit: "20.00"})],
        sales: []
      }

      grid = Print.grid(body, "purchases")
      header = hd(grid)

      # информационните колони винаги остават
      assert "№" in header
      assert "Контрагент" in header
      assert "Вид стока/услуга" in header
      # ненулевите суми остават
      assert "ДО пълен ДК" in header
      assert "ДДС пълен ДК" in header

      # нулевите суми и празните текстови колони се пропускат
      refute "ДО без ДК" in header
      refute "ВОП (покупки)" in header
      refute "Годишна корекция" in header
      refute "Код доставка" in header

      # последният ред е „Общо“ със сумите по оставащите колони
      totals = List.last(grid)
      assert hd(totals) == "Общо"
      idx = Enum.find_index(header, &(&1 == "ДО пълен ДК"))
      assert Enum.at(totals, idx) == "100.00"
      idx_vat = Enum.find_index(header, &(&1 == "ДДС пълен ДК"))
      assert Enum.at(totals, idx_vat) == "20.00"

      # датата е в bg формат
      date_idx = Enum.find_index(header, &(&1 == "Дата"))
      row1 = Enum.at(grid, 1)
      assert Enum.at(row1, date_idx) == "03.11.2026"
    end

    test "продажби: остават само колоните с ненулеви стойности" do
      body = %{
        period: "2026-11",
        company_name: "Тест ООД",
        company_vat: "BG207123456",
        sales: [
          %{
            row: 1,
            branch: "0",
            document_type: "01",
            document_number: "0007",
            document_date: "2026-11-05",
            counterpart_vat_number: "BG999",
            counterpart_name: "Клиент",
            goods: "Услуга",
            delivery_code: "",
            total_base: "1000.00",
            total_vat: "200.00",
            base_20: "1000.00",
            vat_20: "200.00",
            vop_sales_base: "0.00",
            vop_sales_vat: "0.00",
            base_82: "0.00",
            pers_amount: "0.00",
            base_9: "0.00",
            vat_9: "0.00",
            base_0: "0.00",
            base_vod: "0.00",
            base_art: "0.00",
            base_services: "0.00",
            base_69: "0.00",
            base_exempt: "0.00",
            base_tri: "0.00"
          }
        ],
        purchases: []
      }

      header = hd(Print.grid(body, "sales"))
      assert "Общо ДО" in header
      assert "ДО 20%" in header
      assert "ДДС 20%" in header
      refute "ДО 9%" in header
      refute "ВОД" in header
      refute "Освободени" in header
      refute "Тристранни сделки" in header
    end

    test "display_grid форматира сумите в bg формат за PDF" do
      grid = [["Сума"], ["1200.50"]]
      assert Print.display_grid(grid) == [["Сума"], ["1 200,50"]]
    end

    test "register_of и slug" do
      assert Print.register_of("sales") == "sales"
      assert Print.register_of("prodagbi") == "sales"
      assert Print.register_of(nil) == "purchases"
      assert Print.slug("sales") == "dnevnik-prodagbi"
      assert Print.title("purchases") == "Дневник за покупки"
    end
  end
end

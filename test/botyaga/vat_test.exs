defmodule Botyaga.VatTest do
  use ExUnit.Case, async: true

  alias Botyaga.Vat.{Files, Fmt, Line}
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
end

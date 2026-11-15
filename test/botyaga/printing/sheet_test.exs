defmodule Botyaga.Printing.SheetTest do
  use ExUnit.Case, async: true

  alias Botyaga.Printing.Sheet

  test "numbers are numeric cells" do
    assert Sheet.number("1200.00")
    assert Sheet.number("-250.5")
    assert Sheet.number("1 200.00")
    refute Sheet.number("01.10.2026")
    refute Sheet.number("411")
    refute Sheet.number("0000000001")
    refute Sheet.number("Данъчна основа")
  end

  test "bg format uses comma and spaces" do
    num = Sheet.number("1234567.89")
    assert num.value == "1234567.89"
    assert num.bg_text == "1 234 567,89"
    assert Sheet.number("-250.00").bg_text == "-250,00"
  end

  test "xlsx and ods are archives carrying numbers" do
    grid = [["Сума", "1200.00"]]
    xlsx = Sheet.xlsx(grid, true)
    assert binary_part(xlsx, 0, 2) == "PK"
    assert xlsx =~ "<v>1200.00</v>"

    ods = Sheet.ods(grid, true)
    assert binary_part(ods, 0, 2) == "PK"
    assert ods =~ ~s(office:value-type="float")
    assert ods =~ ~s(office:value="1200.00")
    assert ods =~ "1 200,00"
    assert ods =~ ~s(number:language="bg")
  end
end

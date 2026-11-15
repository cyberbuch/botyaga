defmodule Botyaga.Reports.DataTest do
  use ExUnit.Case, async: true

  alias Botyaga.Dec
  alias Botyaga.Reports.Data

  test "range and prefix" do
    assert Data.day_ok("2026-10-01")
    refute Data.day_ok("2026-10-1")
    assert Data.in_range("2026-01-15", "2026-01-01", "2026-10-01", true)
    refute Data.in_range("2026-10-01", "2026-01-01", "2026-10-01", true)
    assert Data.in_range("2026-10-01", "2026-10-01", "2026-10-01", false)
    assert Data.acc_match("4111", "411")
    assert Data.acc_match("501", "50*")
    refute Data.acc_match("601", "50*")
  end

  test "pairs fifo" do
    d = [%{num: "411", rem: Dec.or0("1200")}]
    c = [%{num: "702", rem: Dec.or0("1000")}, %{num: "4532", rem: Dec.or0("200")}]
    got = Data.pair(d, c)
    assert length(got) == 2
    assert Enum.at(got, 0) == {"411", "702", Dec.or0("1000")}
    assert Enum.at(got, 1) == {"411", "4532", Dec.or0("200")}
  end

  test "firm_line" do
    assert Data.firm_line("", "") == ""
    assert Data.firm_line("Фирма", "") == "Фирма"
    assert Data.firm_line("", "123") == "ЕИК 123"
    assert Data.firm_line("Фирма", "123") == "Фирма — ЕИК 123"
  end
end

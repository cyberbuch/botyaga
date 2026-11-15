defmodule Botyaga.Invoicing.MoneyTest do
  use ExUnit.Case, async: true

  alias Botyaga.Invoicing.Money

  test "кредитното обръща знака само веднъж" do
    assert Money.amount_for_doc("03", "120.00") == "-120.00"
    assert Money.amount_for_doc("03", "-120.00") == "-120.00"
    assert Money.amount_for_doc("03", "0.00") == "0.00"
    assert Money.amount_for_doc("01", "120.00") == "120.00"
    assert Money.amount_for_doc("13", "10") == "-10.00"
  end

  test "сумира низове" do
    assert Money.sum_amounts(["1000.00", "200.50"]) == "1200.50"
    assert Money.sum_amounts(["-10.00", "3.00"]) == "-7.00"
    assert Money.cents("1.005") == 101
  end

  test "видове документи по посока" do
    assert Money.valid_for("out", "01")
    assert Money.valid_for("out", "23")
    refute Money.valid_for("in", "04")
    assert Money.valid_for("in", "05")
    assert Money.valid_for("out", "proforma")
    assert Money.requires_original("03")
    refute Money.requires_original("01")
    assert Money.title("03") == "КРЕДИТНО ИЗВЕСТИЕ"
    assert Money.title("01") == "ФАКТУРА"
  end
end

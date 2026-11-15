defmodule Botyaga.Banking.RulesTest do
  use ExUnit.Case, async: true

  alias Botyaga.Banking.Rules

  test "fold транслитерира кирилицата" do
    assert Rules.fold("ПОС трансакция") == "pos transaktsiya"
    assert Rules.fold("POS purchase") == "pos purchase"
    assert Rules.fold("Теглене на каса") == "teglene na kasa"
  end

  test "ключови думи съвпадат между азбуки" do
    assert Rules.contains_keyword("ПОС трансакция 123", "pos")
    assert Rules.contains_keyword("POS PURCHASE CARD", "ПОС")
    refute Rules.contains_keyword("теглене от АТМ", "withdrawal")
    refute Rules.contains_keyword("cash withdrawal", "теглене")
    assert Rules.contains_keyword("НЕВЕЛ 25 ЕООД", "Nevel 25 EOOD")
  end

  test "по-висок приоритет печели" do
    rules = [
      %{
        id: 1,
        name: "нисък",
        keywords: "такса",
        direction: "any",
        priority: 10,
        is_active: 1,
        account_id: 1,
        counterpart_id: 0
      },
      %{
        id: 2,
        name: "висок",
        keywords: "такса,fee",
        direction: "debit",
        priority: 90,
        is_active: 1,
        account_id: 2,
        counterpart_id: 0
      }
    ]

    assert Rules.find_rule(rules, "месечна такса поддръжка", "-12.00").id == 2
  end

  test "посоката филтрира" do
    assert Rules.direction_matches("debit", "-5")
    refute Rules.direction_matches("debit", "5")
    assert Rules.direction_matches("credit", "5")
    assert Rules.direction_matches("any", "5")
  end

  test "company_key пренебрегва правната форма" do
    assert Rules.company_key("НЕВЕЛ 25 ЕООД") == Rules.company_key("Nevel 25")
  end
end

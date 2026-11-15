defmodule Botyaga.ClosingTest do
  use ExUnit.Case, async: true

  alias Botyaga.{Closing, Dec}

  defp acc(id, number), do: %{id: id, number: number, name: "acc #{number}"}

  test "правила от масив и обект, сортирани по дължина" do
    arr = ~s({"closing_map":[{"source":"60201","target":"612"},{"source":"60","target":"611"}]})
    rules = Closing.parse_rules(arr)
    assert length(rules) == 2
    assert hd(rules).source == "60201"

    obj = ~s({"closing_map":{"60":"611","602":"612"}})
    rules = Closing.parse_rules(obj)
    assert length(rules) == 2
    assert Enum.any?(rules, &(&1.source == "60" and &1.target == "611"))

    assert Closing.parse_rules("{}") == []
    assert Closing.parse_rules("not json") == []
    assert hd(Closing.default_rules()).target == "611"
  end

  test "най-дългият префикс печели" do
    rules =
      Closing.parse_rules(
        ~s({"closing_map":[{"source":"60","target":"611"},{"source":"602","target":"612"}]})
      )

    assert Closing.match_rule(rules, "60201").target == "612"
    assert Closing.match_rule(rules, "60101").target == "611"
    assert Closing.match_rule(rules, "702") == nil
  end

  test "планове и балансирани страни" do
    accounts = [acc(1, "60101"), acc(2, "60201"), acc(3, "611"), acc(4, "612"), acc(5, "702")]
    balances = %{1 => Dec.parse("100.00"), 2 => Dec.parse("-25.50"), 3 => Dec.parse("10.00")}

    rules =
      Closing.parse_rules(
        ~s({"closing_map":[{"source":"602","target":"612"},{"source":"60","target":"611"}]})
      )

    {:ok, plans} = Closing.build_plans(accounts, balances, rules)
    assert length(plans) == 2
    assert Enum.at(plans, 0).source.number == "60101"
    assert Enum.at(plans, 0).target.number == "611"
    assert Enum.at(plans, 1).source.number == "60201"

    {sides, total} = Closing.plan_lines(plans)
    assert length(sides) == 4
    assert Enum.at(sides, 0).direction == "credit"
    assert Enum.at(sides, 0).amount == "100.00"
    assert Enum.at(sides, 1).direction == "debit"
    assert Enum.at(sides, 1).amount == "25.50"
    assert total == Dec.parse("125.50")

    debit =
      sides
      |> Enum.filter(&(&1.direction == "debit"))
      |> Enum.map(&Dec.or0(&1.amount))
      |> Enum.sum()

    credit =
      sides
      |> Enum.filter(&(&1.direction == "credit"))
      |> Enum.map(&Dec.or0(&1.amount))
      |> Enum.sum()

    assert debit == credit
  end

  test "целевите сметки не се приключват сами" do
    accounts = [acc(1, "60"), acc(2, "611")]
    balances = %{1 => Dec.parse("10"), 2 => Dec.parse("10")}
    {:ok, plans} = Closing.build_plans(accounts, balances, Closing.default_rules())
    assert length(plans) == 1
    assert hd(plans).source.number == "60"
  end

  test "липсваща целева сметка се отказва" do
    accounts = [acc(1, "60101")]
    balances = %{1 => Dec.parse("5")}
    rules = [%{source: "60", target: "999"}]
    assert {:error, {422, _}} = Closing.build_plans(accounts, balances, rules)
  end
end

defmodule Botyaga.DecTest do
  use ExUnit.Case, async: true

  alias Botyaga.Dec

  test "закръгля парите и количествата както ytbuch" do
    assert Dec.money(Dec.parse("1.005")) == "1.01"
    assert Dec.money(Dec.parse("-10")) == "-10.00"
    assert Dec.qty(Dec.parse("1.23456")) == "1.2346"
  end

  test "празен и нечетим низ" do
    assert Dec.parse("") == 0
    assert Dec.or0("нещо") == 0
    assert Dec.parse("abc") == nil
    assert Dec.parse("12,5") == 12_500_000
    assert Dec.parse(" 1 234,56 ") == 1_234_560_000
  end

  test "умножение и деление със закръгляне" do
    assert Dec.mul(Dec.parse("10"), Dec.parse("0.333333")) == Dec.parse("3.33333")
    assert Dec.div(Dec.parse("10"), Dec.parse("3")) == Dec.parse("3.333333")
    assert Dec.div(Dec.parse("1"), 0) == nil
  end
end

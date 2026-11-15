defmodule Botyaga.Printing.WordsTest do
  use ExUnit.Case, async: true

  alias Botyaga.Printing.Words

  test "euro and leva" do
    assert Words.words("1200.00", "EUR") == "хиляда двеста евро"
    assert Words.words("1.05", "EUR") == "един евро и 05 евроцента"
    assert Words.words("-10.00", "BGN") == "минус десет лева"
    assert Words.words("1.00", "BGN") == "една лев"
    assert Words.words("21", "BGN") == "двадесет и една лева"
  end

  test "zero and millions" do
    assert Words.words("0.00", "EUR") == "нула евро"
    assert Words.words("1000000.00", "EUR") == "един милион евро"
    assert Words.words("2000000.00", "EUR") == "два милиона евро"
  end
end

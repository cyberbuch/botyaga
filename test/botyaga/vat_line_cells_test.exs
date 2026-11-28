defmodule Botyaga.Vat.LineCellsTest do
  @moduledoc "Регресионен тест: частичен данъчен кредит (кл.40) с цяла аритметика."

  use ExUnit.Case, async: true

  alias Botyaga.Vat.Line

  test "точна половин стотинка се закръгля нагоре (half away from zero), не надолу от float" do
    # кл.42 = 0.50 (50 стотинки), кл.33 = 0.29 → 50 × 0.29 = 14.5 → 15
    # (с float: 50 * 0.29 = 14.4999… → даваше 14)
    cells = Line.cells() |> Map.merge(%{m33: "0.29", p41: 0, p42: 50, p43: 0, s20: 1000})
    finished = Line.cells_finish(cells)
    assert finished.r40 == 15
    assert finished.r50 == 985
    assert finished.r60 == 0
  end

  test "отрицателна половинка се закръгля далеч от нулата" do
    cells = Line.cells() |> Map.merge(%{m33: "0.29", p41: 0, p42: -50, p43: 0, s20: 0})
    finished = Line.cells_finish(cells)
    assert finished.r40 == -15
    # diff = s20 - r40 = 0 - (-15) = 15 ≥ 0 → в кл.50
    assert finished.r50 == 15
    assert finished.r60 == 0
  end

  test "без частичен кредит (кл.33 = 0) кл.40 = кл.41 + кл.43" do
    cells = Line.cells() |> Map.merge(%{m33: "0.00", p41: 100, p42: 999, p43: 7, s20: 200})
    finished = Line.cells_finish(cells)
    assert finished.r40 == 107
    assert finished.r50 == 93
  end
end

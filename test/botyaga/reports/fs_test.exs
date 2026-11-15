defmodule Botyaga.Reports.FSTest do
  use ExUnit.Case, async: true

  alias Botyaga.Reports.FS

  test "parses account ref and corr" do
    assert {:ok, t} = FS.parse("+304Д -241К")
    assert length(t) == 2
    assert Enum.at(t, 0) == {false, {:acct, "304", "D"}}
    assert Enum.at(t, 1) == {true, {:acct, "241", "C"}}

    assert {:ok, [{false, {:corr, "702", "304"}}]} = FS.parse("702Д/304К")

    assert {:ok, r} = FS.parse("+601ОД+@pl.e.5a")
    assert Enum.at(r, 0) == {false, {:acct, "601", "TD"}}
    assert Enum.at(r, 1) == {false, {:at, "pl.e.5a"}}

    assert {:error, _} = FS.parse("+304")
  end

  test "check counts tokens" do
    assert {:ok, 2} = FS.check("+304Д -241К")
    assert {:ok, 0} = FS.check("")
    assert {:ok, 1} = FS.check("50*Д/411К")
    assert {:error, _} = FS.check("+304")
    assert {:error, _} = FS.check("+")
  end

  test "minus sign variant and wildcards" do
    assert {:ok, [{true, {:acct, "121", "OD"}}]} = FS.parse("−121НД")
    assert {:ok, [{false, {:acct, "50*", "D"}}]} = FS.parse("50*Д")
  end
end

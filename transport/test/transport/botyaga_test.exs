defmodule Transport.BotyagaTest do
  use ExUnit.Case, async: true

  alias Transport.Botyaga

  test "решението по реда от botyaga" do
    assert Botyaga.decide([], 0) == {:error, {401, "потребителят не съществува"}}
    assert Botyaga.decide([[1, 3, 0, true, true]], 3) == :ok
    assert Botyaga.decide([[1, 3, 1, false, true]], 3) == :ok

    assert Botyaga.decide([[1, 3, 0, false, true]], 3) ==
             {:error, {403, "нямате достъп до тази фирма"}}

    assert Botyaga.decide([[1, 4, 1, true, true]], 3) ==
             {:error, {401, "сесията е приключена — влезте отново"}}

    assert Botyaga.decide([[0, 3, 1, true, true]], 3) ==
             {:error, {403, "потребителят е неактивен"}}

    # несъществуваща фирма — дори за суперадмин
    assert Botyaga.decide([[1, 3, 1, false, false]], 3) ==
             {:error, {404, "фирмата не е намерена"}}
  end
end

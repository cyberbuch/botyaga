defmodule Botyaga.RatesTest do
  use ExUnit.Case, async: true

  alias Botyaga.Rates

  @ecb """
  <?xml version="1.0" encoding="UTF-8"?>
  <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01">
    <Cube>
      <Cube time="2026-01-15">
        <Cube currency="USD" rate="1.08"/>
        <Cube currency="BGN" rate="1.95583"/>
      </Cube>
      <Cube time="2026-01-14">
        <Cube currency="USD" rate="1.07"/>
      </Cube>
    </Cube>
  </gesmes:Envelope>
  """

  test "cubes parses time and currency/rate" do
    assert {:ok, rows} = Rates.cubes(@ecb)
    assert {"USD", "1.08", "2026-01-15"} in rows
    assert {"BGN", "1.95583", "2026-01-15"} in rows
    assert {"USD", "1.07", "2026-01-14"} in rows
    assert length(rows) == 3
  end

  test "cubes rejects invalid xml" do
    assert {:error, "невалиден XML от ЕЦБ"} = Rates.cubes("<html>няма cube</html>")
    assert {:ok, []} = Rates.cubes("няма xml")
  end

  test "cross_value" do
    assert {:ok, "1.810954"} = Rates.cross_value("1.08", "1.95583")
    assert {:error, {422, "курсът е 0"}} = Rates.cross_value("0", "1")
    assert {:error, {422, "невалиден курс"}} = Rates.cross_value("abc", "1")
  end
end

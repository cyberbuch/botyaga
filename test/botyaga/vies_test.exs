defmodule Botyaga.ViesTest do
  use ExUnit.Case, async: true

  alias Botyaga.Vies

  test "normalize keeps only ascii alnum uppercased" do
    assert Vies.normalize(" bg 123-456 ") == "BG123456"
    assert Vies.normalize("BG123456789") == "BG123456789"
  end

  test "shape_ok validates EU prefix and length" do
    assert Vies.shape_ok("BG123456789")
    assert Vies.shape_ok("DE123456789")
    assert Vies.shape_ok("EL123456789")
    refute Vies.shape_ok("US123456789")
    refute Vies.shape_ok("BG1")
    refute Vies.shape_ok("BG1234567890123456")
  end
end

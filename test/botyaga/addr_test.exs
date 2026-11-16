defmodule Botyaga.AddrTest do
  use ExUnit.Case, async: true

  alias Botyaga.Addr

  test "split_local extracts street, number, city, post, region" do
    p = Addr.split_local("ул. Витоша 15, 1000 София", "BG", "", "")
    assert p.street_name == "Витоша"
    assert p.building_number == "15"
    assert p.city == "София"
    assert p.post_code == "1000"
    assert p.region == "BG-22"
    assert p.address_type == "StreetAddress"
    assert p.ok
  end

  test "drops trailing country line" do
    p = Addr.split_local("ул. Витоша 15, 1000 София, BG", "", "", "")
    assert p.city == "София"
    assert p.country == "BG"
  end

  test "empty and --- are not ok" do
    refute Addr.split_local("", "BG", "", "").ok
    refute Addr.split_local("---", "BG", "", "").ok
  end

  test "hints are respected" do
    p = Addr.split_local("Витоша 15", "BG", "София", "1000")
    assert p.city == "София"
    assert p.post_code == "1000"
    assert p.street_name == "Витоша"
  end

  test "parts_json carries parse_ok and note" do
    p = Addr.split_local("ул. Витоша 15, 1000 София", "BG", "", "")
    json = Addr.parts_json(p, "бележка")
    assert json.parse_ok == true
    assert json.parse_note == "бележка"
    assert json.region == "BG-22"
  end
end

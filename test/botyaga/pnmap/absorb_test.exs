defmodule Botyaga.Pnmap.AbsorbTest do
  use ExUnit.Case, async: true

  alias Botyaga.Invoicing.Money
  alias Botyaga.Pnmap.Absorb

  test "absorbs vat without rounding drift" do
    lines = [
      %{
        "description" => "Артикул 1",
        "quantity" => "3",
        "unit" => "C62",
        "unit_price" => "10.00",
        "vat_rate" => "20",
        "net_amount" => "30.00",
        "vat_amount" => "6.00",
        "total_amount" => "36.00"
      },
      %{
        "description" => "Артикул 2",
        "quantity" => "3",
        "unit" => "C62",
        "unit_price" => "3.33",
        "vat_rate" => "20",
        "net_amount" => "9.99",
        "vat_amount" => "2.00",
        "total_amount" => "11.99"
      }
    ]

    {lines, net, tot} = Absorb.absorb(lines, "39.99", "8.00", "47.99")
    assert net == "47.99"
    assert tot == "47.99"
    assert Enum.at(lines, 0)["net_amount"] == "36.00"
    assert Enum.at(lines, 0)["vat_rate"] == "0"
    assert Enum.at(lines, 0)["vat_amount"] == "0.00"
    assert Enum.at(lines, 1)["net_amount"] == "11.99"
    assert Enum.at(lines, 1)["total_amount"] == "11.99"
    assert Enum.at(lines, 1)["unit_price"] == "4.00"
  end

  test "distributes header vat across net-only lines" do
    lines = [
      %{
        "description" => "Стока А",
        "quantity" => "1",
        "unit_price" => "33.33",
        "vat_rate" => "0",
        "net_amount" => "33.33",
        "vat_amount" => "",
        "total_amount" => "33.33"
      },
      %{
        "description" => "Стока Б",
        "quantity" => "1",
        "unit_price" => "33.33",
        "vat_rate" => "0",
        "net_amount" => "33.33",
        "vat_amount" => "",
        "total_amount" => "33.33"
      },
      %{
        "description" => "Стока В",
        "quantity" => "1",
        "unit_price" => "33.34",
        "vat_rate" => "0",
        "net_amount" => "33.34",
        "vat_amount" => "",
        "total_amount" => "33.34"
      }
    ]

    {lines, net, tot} = Absorb.absorb(lines, "100.00", "20.00", "120.00")
    assert net == "120.00"
    assert tot == "120.00"
    sum = Enum.sum(Enum.map(lines, &Money.cents(&1["net_amount"])))
    assert sum == 12000
  end

  test "empty lines fall back to document totals" do
    {[], net, tot} = Absorb.absorb([], "100.00", "20.00", "120.00")
    assert net == "120.00"
    assert tot == "120.00"
  end
end

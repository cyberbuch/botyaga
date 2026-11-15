defmodule Botyaga.Reports.Stock do
  @moduledoc """
  Справка за склада като `kind=stock` на `/v1/reports`: приход, разход и наличност
  към дата. Чете същите движения като преизчислението. Порт на `stock_report.rs#sheet`.
  """

  alias Botyaga.Companies.Company
  alias Botyaga.Repo
  alias Botyaga.Reports.Data
  alias Botyaga.Stock.Replay

  def sheet(company_id, from, to, loc) do
    {:ok, out} = Replay.explain(company_id, to)

    in_range = fn f ->
      f.date >= from and f.date <= to and (loc <= 0 or f.location_id == loc)
    end

    receipts = Enum.filter(out.flows, &(&1.kind == "in" and in_range.(&1)))
    issues = Enum.filter(out.flows, &(&1.kind == "out" and in_range.(&1)))
    balances = Enum.filter(out.balances, &(loc <= 0 or &1.location_id == loc))

    firm = Repo.get(Company, company_id)
    name = (firm && firm.name) || ""
    eik = (firm && firm.eik) || ""

    grid = []
    line = Data.firm_line(name, eik)
    grid = if line != "", do: grid ++ [[line]], else: grid
    grid = grid ++ [["Склад", from, to]]
    grid = push_flows(grid, "Приход", receipts)
    grid = push_flows(grid, "Разход", issues)
    grid = grid ++ [[], ["Наличности"], ["Артикул", "Обект", "Количество", "Стойност"]]

    grid =
      grid ++
        Enum.map(
          balances,
          &[&1.product_name, Integer.to_string(&1.location_id), &1.quantity, &1.value]
        )

    body = %{
      from: from,
      to: to,
      receipts: Enum.map(receipts, &flow_json/1),
      issues: Enum.map(issues, &flow_json/1),
      balances: Enum.map(balances, &bal_json/1),
      warnings: out.warnings
    }

    {:ok, %{body: body, slug: "sklad", grid: grid}}
  end

  defp flow_json(f) do
    %{
      date: f.date,
      document: f.doc,
      kind: f.kind,
      reason: f.reason,
      product_id: f.product_id,
      product_name: f.product_name,
      location_id: f.location_id,
      quantity: f.quantity,
      value: f.value
    }
  end

  defp bal_json(b) do
    %{
      product_id: b.product_id,
      product_name: b.product_name,
      location_id: b.location_id,
      quantity: b.quantity,
      value: b.value
    }
  end

  defp push_flows(grid, title, rows) do
    grid ++
      [
        [],
        [title],
        ["Дата", "Документ", "Артикул", "Обект", "Количество", "Стойност", "Основание"]
      ] ++
      Enum.map(
        rows,
        &[
          &1.date,
          &1.doc,
          &1.product_name,
          Integer.to_string(&1.location_id),
          &1.quantity,
          &1.value,
          &1.reason
        ]
      )
  end
end

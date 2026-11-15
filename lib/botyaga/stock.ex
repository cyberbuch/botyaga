defmodule Botyaga.Stock do
  @moduledoc "Наличност по обект и справка за склада (приход, разход, наличности)."

  import Ecto.Query

  alias Botyaga.{Catalog, Dec, Params, Repo}
  alias Botyaga.Stock.{Lot, Replay}

  def at_location(company_id, location_id) do
    location_id = Params.id(location_id || 0)

    products =
      Repo.all(
        from(p in Catalog.Product,
          where: p.company_id == ^company_id and p.is_inventory == 1,
          order_by: [asc: p.id]
        )
      )

    lots =
      if products == [] do
        []
      else
        ids = Enum.map(products, & &1.id)
        Repo.all(from(l in Lot, where: l.product_id in ^ids, order_by: [asc: l.id]))
      end

    items =
      Enum.reduce(products, [], fn p, acc ->
        sum =
          lots
          |> Enum.filter(&(&1.product_id == p.id and &1.location_id == location_id))
          |> Enum.reduce(0, fn lot, s -> s + Dec.or0(lot.quantity_remaining) end)

        if sum > 0 do
          acc ++
            [
              %{
                product_id: p.id,
                name: p.name,
                code: p.code,
                unit: p.unit,
                quantity: Dec.qty(sum),
                unit_cost: p.cost_price
              }
            ]
        else
          acc
        end
      end)

    %{items: items, count: length(items), location_id: location_id}
  end

  def report(company_id, params) do
    to = params["to"] || ""
    to = if iso?(to), do: to, else: "9999-12-31"
    from = params["from"] || ""
    from = if iso?(from), do: from, else: "0001-01-01"
    loc = Params.id(params["location_id"] || 0)

    with {:ok, out} <- Replay.explain(company_id, to) do
      in_range = fn f ->
        f.date >= from and f.date <= to and (loc <= 0 or f.location_id == loc)
      end

      receipts =
        out.flows |> Enum.filter(&(&1.kind == "in" and in_range.(&1))) |> Enum.map(&flow_json/1)

      issues =
        out.flows |> Enum.filter(&(&1.kind == "out" and in_range.(&1))) |> Enum.map(&flow_json/1)

      balances =
        out.balances |> Enum.filter(&(loc <= 0 or &1.location_id == loc)) |> Enum.map(&bal_json/1)

      {:ok,
       %{
         from: from,
         to: if(to == "9999-12-31", do: "", else: to),
         receipts: receipts,
         issues: issues,
         balances: balances,
         warnings: out.warnings
       }}
    end
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

  defp iso?(s), do: String.length(s) == 10 and String.at(s, 4) == "-" and String.at(s, 7) == "-"
end

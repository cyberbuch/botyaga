defmodule Botyaga.Assets.Ops do
  @moduledoc "Амортизация и събития по ДМА. Един запис: Дт 603 / Кт 241."

  import Ecto.Query

  alias Botyaga.{Assets, Audit, Catalog, Companies, Dec, Journal, Params, Periods, Repo}
  alias Botyaga.Assets.{Asset, Event}

  def preview(company_id) do
    rows = active_rows(company_id)

    {items, total} =
      Enum.reduce(rows, {[], 0}, fn asset, {items, total} ->
        amount = monthly(asset)

        {items ++
           [
             %{
               id: asset.id,
               name: asset.name,
               method: asset.depreciation_method,
               monthly_amount: Dec.money(amount)
             }
           ], total + amount}
      end)

    {:ok, %{items: items, total_amount: Dec.money(total)}}
  end

  def post_dep(company_id, sub, params) do
    with {:ok, period} <- required(params, "period"),
         :ok <- Periods.assert_open(company_id, period),
         {:ok, exp} <- by_number(company_id, "603", "липсва сметка 603 (разход за амортизации)"),
         {:ok, acc} <- by_number(company_id, "241", "липсва сметка 241 (амортизация на ДМА)") do
      rows = active_rows(company_id)

      {next, total} =
        Enum.reduce(rows, {[], 0}, fn asset, {next, total} ->
          amount = monthly(asset)
          accum = Dec.or0(asset.accumulated_depreciation) + amount
          {next ++ [{asset.id, Dec.money(accum)}], total + amount}
        end)

      total_s = Dec.money(total)

      {:ok, entry_id} =
        Repo.transaction(fn ->
          {:ok, entry_id} =
            Journal.write_entry(
              company_id,
              period,
              "depreciation",
              0,
              "",
              "Месечна амортизация на ДМА",
              0,
              "",
              month_of(period),
              [
                %{account: exp, direction: "debit", amount: total_s},
                %{account: acc, direction: "credit", amount: total_s}
              ]
            )

          Enum.each(next, fn {id, accum} ->
            Repo.update_all(from(a in Asset, where: a.id == ^id),
              set: [accumulated_depreciation: accum, tax_accumulated_depreciation: accum]
            )
          end)

          entry_id
        end)

      Audit.record(
        company_id,
        sub,
        "journal",
        entry_id,
        period,
        "create",
        "Осчетоводена месечна амортизация на ДМА (#{period}), сума #{total_s}",
        "",
        total_s,
        nil,
        nil
      )

      {:ok,
       %{
         id: entry_id,
         document_type: "depreciation",
         description: "Месечна амортизация на ДМА",
         total_amount: total_s
       }}
    end
  end

  def revalue(company_id, id, params) do
    with {:ok, asset} <- Assets.fetch(company_id, id),
         {:ok, new_value} <- money_of(required_string(params, "new_value")) do
      prev = asset.cost || "0.00"
      asset = Repo.update!(Ecto.Changeset.change(asset, cost: new_value))
      add_event(asset.id, "revaluation", date_of(params), new_value, prev, "", reason(params))
      {:ok, Assets.asset_json(asset)}
    end
  end

  def move(company_id, id, params) do
    with {:ok, asset} <- Assets.fetch(company_id, id) do
      location_id = Params.integer(params, "location_id") || 0

      with :ok <- ensure_location(location_id, asset.company_id) do
        place = location_name(location_id, asset.company_id)
        asset = Repo.update!(Ecto.Changeset.change(asset, location_id: location_id))
        add_event(asset.id, "movement", date_of(params), "0.00", "", place, reason(params))
        {:ok, Assets.asset_json(asset)}
      end
    end
  end

  def conserve(company_id, id, params),
    do: flag_event(company_id, id, params, 1, "conservation_start")

  def end_conserve(company_id, id, params),
    do: flag_event(company_id, id, params, 0, "conservation_end")

  def dispose(company_id, id, params) do
    with {:ok, asset} <- Assets.fetch(company_id, id) do
      kind = string(params, "disposal_type", "write_off")
      status = if kind == "sale", do: "sold", else: "disposed"
      amount = money_of(string(params, "sale_amount", "0"))

      case amount do
        {:ok, amount} ->
          asset = Repo.update!(Ecto.Changeset.change(asset, status: status))
          add_event(asset.id, "disposal", date_of(params), amount, "", "", reason(params))
          {:ok, Assets.asset_json(asset)}

        error ->
          error
      end
    end
  end

  def events(company_id, id) do
    with {:ok, asset} <- Assets.fetch(company_id, id) do
      rows = Repo.all(from(e in Event, where: e.asset_id == ^asset.id, order_by: [asc: e.id]))

      items =
        Enum.map(rows, fn e ->
          %{
            id: e.id,
            asset_id: e.asset_id,
            event_type: e.event_type,
            event_date: e.event_date,
            amount: e.amount,
            prev_value: e.prev_value,
            location: e.location,
            reason: e.reason
          }
        end)

      {:ok, items}
    end
  end

  ## Вътрешни

  defp flag_event(company_id, id, params, flag, kind) do
    with {:ok, asset} <- Assets.fetch(company_id, id) do
      asset = Repo.update!(Ecto.Changeset.change(asset, is_conserved: flag))
      add_event(asset.id, kind, date_of(params), "0.00", "", "", reason(params))
      {:ok, Assets.asset_json(asset)}
    end
  end

  defp active_rows(company_id) do
    Repo.all(from(a in Asset, where: a.company_id == ^company_id, order_by: [asc: a.id]))
    |> Enum.filter(&(&1.status == "active" and &1.is_conserved == 0))
  end

  def monthly(asset) do
    cost = Dec.or0(asset.cost)
    salvage = Dec.or0(asset.salvage_value)
    accum = Dec.or0(asset.accumulated_depreciation)
    rate = Dec.or0(asset.accounting_depreciation_rate)

    base =
      if asset.depreciation_method == "declining" do
        cost - accum
      else
        cost - salvage
      end

    base = max(base, 0)
    year = Dec.div(Dec.mul(base, rate), Dec.parse("100")) || 0
    raw = Dec.div(year, Dec.parse("12")) || 0
    Dec.parse(Dec.money(raw)) || 0
  end

  defp by_number(company_id, number, message) do
    case Repo.get_by(Catalog.Account, number: number, company_id: company_id) do
      nil -> {:error, {422, message}}
      account -> {:ok, account}
    end
  end

  defp add_event(asset_id, kind, date, amount, prev, location, reason) do
    Repo.insert!(%Event{
      asset_id: asset_id,
      event_type: kind,
      event_date: date,
      amount: amount,
      prev_value: prev,
      location: location,
      reason: reason
    })
  end

  defp ensure_location(location_id, _company_id) when location_id <= 0, do: :ok

  defp ensure_location(location_id, company_id) do
    if Repo.get_by(Companies.Location, id: location_id, company_id: company_id) == nil do
      {:error, {404, "обектът не е намерен"}}
    else
      :ok
    end
  end

  defp location_name(location_id, _company_id) when location_id <= 0, do: ""

  defp location_name(location_id, company_id) do
    case Repo.get_by(Companies.Location, id: location_id, company_id: company_id) do
      %{name: name} when name not in [nil, ""] -> name
      _ -> Integer.to_string(location_id)
    end
  end

  defp month_of(date), do: if(String.length(date) >= 7, do: String.slice(date, 0, 7), else: date)

  defp date_of(params), do: string(params, "event_date")
  defp reason(params), do: string(params, "reason")

  defp money_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидна стойност"}}
      value -> {:ok, Dec.money(value)}
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp required_string(params, key) do
    case required(params, key) do
      {:ok, value} -> value
      {:error, _} -> ""
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

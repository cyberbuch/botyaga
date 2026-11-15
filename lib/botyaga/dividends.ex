defmodule Botyaga.Dividends do
  @moduledoc "Дивиденти към действителните собственици. Плащането не пише в дневника."

  import Ecto.Query

  alias Botyaga.{Audit, Companies, Dec, Params, Repo}
  alias Botyaga.Companies.Owner
  alias Botyaga.Dividends.{Distribution, Dividend}

  def index(company_id) do
    owners = owners_of(company_id)
    currency = currency_of(company_id)
    kids = kids_of(company_id)

    items =
      Repo.all(from(d in Distribution, where: d.company_id == ^company_id, order_by: [asc: d.id]))
      |> Enum.map(&pack(&1, kids, false))

    %{items: items, owners: Enum.map(owners, &owner_json/1), currency: currency}
  end

  def show(company_id, id) do
    with {:ok, dist} <- fetch(company_id, id), do: {:ok, pack(dist, kids_of(company_id), true)}
  end

  def create(company_id, sub, params) do
    with {:ok, year} <- year_of(Params.integer(params, "year")),
         {:ok, raw_total} <- required(params, "total_amount"),
         {:ok, total} <- positive(raw_total),
         {:ok, date} <- required(params, "decision_date"),
         {:ok, rate} <- rate_of(string(params, "tax_rate", "5")),
         {:ok, shares} <- split(company_id, total, rate) do
      number = string(params, "decision_number")
      notes = string(params, "notes")

      {:ok, dist} =
        Repo.transaction(fn ->
          dist =
            Repo.insert!(%Distribution{
              company_id: company_id,
              year: year,
              total_amount: Dec.money(total),
              decision_date: date,
              decision_number: number,
              status: "draft",
              notes: notes
            })

          insert_shares(company_id, dist.id, date, shares)
          dist
        end)

      after_value = pack(dist, kids_of(company_id), true)

      Audit.record(
        company_id,
        sub,
        "dividend",
        dist.id,
        number,
        "create",
        "Създаден протокол за дивидент № #{number} (#{year}), сума #{Dec.money(total)}",
        "",
        Dec.money(total),
        nil,
        after_value
      )

      {:ok, after_value}
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, dist} <- fetch(company_id, id) do
      cur = pack(dist, kids_of(company_id), true)

      if touches?(params) and any_paid?(cur) do
        {:error,
         {422,
          "Не може да се променя сумата или данъкът при изплатени дивиденти. Първо отменете плащанията."}}
      else
        with :ok <- maybe_status(dist, params),
             {:ok, dist} <- maybe_recompute(company_id, dist, cur, params) do
          after_value = pack(dist, kids_of(company_id), true)

          Audit.record(
            company_id,
            sub,
            "dividend",
            dist.id,
            dist.decision_number,
            "update",
            "Редактиран протокол за дивидент № #{dist.decision_number}, сума #{cur.total_amount} → #{after_value.total_amount}",
            cur.total_amount,
            after_value.total_amount,
            cur,
            after_value
          )

          {:ok, after_value}
        end
      end
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, dist} <- fetch(company_id, id) do
      cur = pack(dist, kids_of(company_id), true)

      cond do
        any_paid?(cur) ->
          {:error, {422, "Не може да се изтрие разпределение с изплатени дивиденти."}}

        dist.status != "draft" ->
          {:error,
           {422, "Може да се изтрие само чернова. Първо върнете разпределението в чернова."}}

        true ->
          Repo.delete_all(from(d in Dividend, where: d.distribution_id == ^dist.id))
          Repo.delete!(dist)

          Audit.record(
            company_id,
            sub,
            "dividend",
            dist.id,
            dist.decision_number,
            "delete",
            "Изтрит протокол за дивидент № #{dist.decision_number}, сума #{cur.total_amount}",
            cur.total_amount,
            "",
            cur,
            nil
          )

          {:ok, nil}
      end
    end
  end

  def pay(company_id, id, params) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Params.flag(params, "is_paid") do
        nil ->
          {:error, {422, "is_paid е задължително"}}

        {:error, _} ->
          {:error, {422, "is_paid е задължително"}}

        paid ->
          case Repo.get_by(Dividend, id: id, company_id: company_id) do
            nil ->
              {:error, {404, "Дивидентът не е намерен"}}

            dividend ->
              with {:ok, dist} <- fetch(company_id, dividend.distribution_id),
                   :ok <- approved(dist) do
                payment_date =
                  if paid == 0, do: "", else: default_date(params, dividend.decision_date)

                Repo.update!(
                  Ecto.Changeset.change(dividend, is_paid: paid, payment_date: payment_date)
                )

                refresh_status(dividend.distribution_id, dist.status)
                show(company_id, dividend.distribution_id)
              end
          end
      end
    end
  end

  ## Вътрешни

  defp maybe_status(dist, params) do
    case Params.str(params, "status") do
      {:present, status} ->
        if status in ["draft", "approved", "partially_paid", "paid"] do
          Repo.update!(Ecto.Changeset.change(dist, status: status))
          :ok
        else
          {:error, {422, "невалиден статус"}}
        end

      _ ->
        :ok
    end
  end

  defp maybe_recompute(company_id, dist, cur, params) do
    if touches?(params) do
      with {:ok, year} <- year_of(pick_int(params, "year", dist.year)),
           {:ok, total} <- positive(pick(params, "total_amount", dist.total_amount)),
           {:ok, date} <- required_date(pick(params, "decision_date", dist.decision_date)),
           {:ok, rate} <- rate_of(string(params, "tax_rate", current_rate(cur))),
           {:ok, shares} <- split(company_id, total, rate) do
        dist =
          Repo.update!(
            Ecto.Changeset.change(dist,
              year: year,
              total_amount: Dec.money(total),
              decision_date: date,
              decision_number: pick(params, "decision_number", dist.decision_number),
              notes: pick(params, "notes", dist.notes)
            )
          )

        Repo.delete_all(from(d in Dividend, where: d.distribution_id == ^dist.id))
        insert_shares(company_id, dist.id, date, shares)
        {:ok, dist}
      end
    else
      dist =
        Repo.update!(
          Ecto.Changeset.change(dist,
            decision_number: pick(params, "decision_number", dist.decision_number),
            notes: pick(params, "notes", dist.notes)
          )
        )

      {:ok, dist}
    end
  end

  defp split(company_id, total, rate) do
    owners = owners_of(company_id) |> Enum.filter(&(&1.share > 0))

    if owners == [] do
      {:error, {422, "Няма действителни собственици с процент. Добавете ги в Настройки → SAF-T."}}
    else
      sum_pct = Enum.sum(Enum.map(owners, & &1.share))

      if sum_pct <= 0 do
        {:error, {422, "Общият процент на собственост е 0"}}
      else
        rate_v = Dec.or0(rate)
        hundred = Dec.parse("100")
        n = length(owners)

        {shares, _assigned} =
          owners
          |> Enum.with_index()
          |> Enum.reduce({[], 0}, fn {owner, i}, {out, assigned} ->
            gross =
              if i + 1 == n do
                total - assigned
              else
                raw = Dec.div(Dec.mul(total, owner.share), sum_pct) || 0
                g = Dec.parse(Dec.money(raw)) || 0
                g
              end

            assigned = if i + 1 == n, do: assigned, else: assigned + gross
            tax_raw = Dec.div(Dec.mul(gross, rate_v), hundred) || 0
            tax = Dec.parse(Dec.money(tax_raw)) || 0
            net = gross - tax
            {out ++ [%{owner: owner, gross: gross, tax: tax, net: net, rate: rate}], assigned}
          end)

        {:ok, shares}
      end
    end
  end

  defp insert_shares(company_id, dist_id, date, shares) do
    Enum.each(shares, fn share ->
      name = "#{share.owner.first} #{share.owner.last}" |> String.trim()

      Repo.insert!(%Dividend{
        company_id: company_id,
        distribution_id: dist_id,
        beneficial_owner_id: share.owner.id,
        owner_name: name,
        owner_egn: share.owner.egn,
        ownership_percentage: share.owner.pct,
        gross_amount: Dec.money(share.gross),
        tax_rate: share.rate,
        tax_amount: Dec.money(share.tax),
        net_amount: Dec.money(share.net),
        decision_date: date,
        payment_date: "",
        is_paid: 0,
        notes: ""
      })
    end)
  end

  defp owners_of(company_id) do
    Repo.all(from(o in Owner, where: o.company_id == ^company_id, order_by: [asc: o.id]))
    |> Enum.map(fn o ->
      %{
        id: o.id,
        first: o.first_name_bg,
        last: o.last_name_bg,
        egn: o.egn,
        pct: o.ownership_percentage,
        share: Dec.or0(o.ownership_percentage)
      }
    end)
  end

  defp owner_json(o),
    do: %{
      id: o.id,
      first_name_bg: o.first,
      last_name_bg: o.last,
      egn: o.egn,
      ownership_percentage: o.pct
    }

  defp currency_of(company_id) do
    case Companies.get_company(company_id) do
      nil -> "EUR"
      company -> if String.trim(company.currency || "") == "", do: "EUR", else: company.currency
    end
  end

  defp kids_of(company_id) do
    Repo.all(from(d in Dividend, where: d.company_id == ^company_id, order_by: [asc: d.id]))
  end

  defp pack(dist, kids, with_divs) do
    mine = Enum.filter(kids, &(&1.distribution_id == dist.id))
    total_net = Enum.reduce(mine, 0, fn k, s -> s + Dec.or0(k.net_amount) end)
    total_tax = Enum.reduce(mine, 0, fn k, s -> s + Dec.or0(k.tax_amount) end)

    total_paid =
      mine
      |> Enum.filter(&(&1.is_paid != 0))
      |> Enum.reduce(0, fn k, s -> s + Dec.or0(k.net_amount) end)

    item = %{
      id: dist.id,
      year: dist.year,
      total_amount: dist.total_amount,
      decision_date: dist.decision_date,
      decision_number: dist.decision_number,
      status: dist.status,
      notes: dist.notes,
      dividends_count: length(mine),
      total_net: Dec.money(total_net),
      total_paid: Dec.money(total_paid),
      total_tax: Dec.money(total_tax)
    }

    if with_divs do
      Map.put(item, :dividends, Enum.map(mine, &dividend_json/1))
    else
      item
    end
  end

  defp dividend_json(d) do
    %{
      id: d.id,
      beneficial_owner_id: d.beneficial_owner_id,
      owner_name: d.owner_name,
      owner_egn: d.owner_egn,
      ownership_percentage: d.ownership_percentage,
      gross_amount: d.gross_amount,
      tax_rate: d.tax_rate,
      tax_amount: d.tax_amount,
      net_amount: d.net_amount,
      is_paid: d.is_paid,
      payment_date: d.payment_date
    }
  end

  defp fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(Distribution, id: id, company_id: company_id) do
        nil -> {:error, {404, "Разпределението не е намерено"}}
        dist -> {:ok, dist}
      end
    end
  end

  defp refresh_status(dist_id, old) do
    kids = Repo.all(from(d in Dividend, where: d.distribution_id == ^dist_id, select: d.is_paid))
    n = length(kids)
    paid = Enum.count(kids, &(&1 != 0))

    status =
      cond do
        n > 0 and paid == n -> "paid"
        paid > 0 -> "partially_paid"
        old in ["paid", "partially_paid"] -> "approved"
        true -> old
      end

    Repo.update_all(from(d in Distribution, where: d.id == ^dist_id), set: [status: status])
  end

  defp approved(%Distribution{status: "draft"}),
    do: {:error, {422, "Одобрете разпределението преди изплащане"}}

  defp approved(_), do: :ok

  defp default_date(params, decision) do
    case Params.str(params, "payment_date") do
      {:present, value} -> if String.trim(value) == "", do: decision, else: value
      _ -> decision
    end
  end

  defp touches?(params),
    do:
      Enum.any?(["year", "total_amount", "tax_rate", "decision_date"], &Map.has_key?(params, &1))

  defp any_paid?(cur), do: cur |> Map.get(:dividends, []) |> Enum.any?(&(&1.is_paid != 0))

  defp current_rate(cur) do
    case Map.get(cur, :dividends, []) do
      [first | _] -> first.tax_rate || "5"
      [] -> "5"
    end
  end

  defp year_of(value) do
    year = value || 0
    if year in 1990..2100, do: {:ok, year}, else: {:error, {422, "невалидна финансова година"}}
  end

  defp positive(raw) do
    case Dec.parse(raw) do
      nil ->
        {:error, {422, "невалидна стойност"}}

      value ->
        if value <= 0 do
          {:error, {422, "сумата за разпределяне трябва да е по-голяма от 0"}}
        else
          {:ok, Dec.parse(Dec.money(value)) || value}
        end
    end
  end

  defp rate_of(raw) do
    case Dec.parse(raw) do
      nil ->
        {:error, {422, "невалидна стойност"}}

      value ->
        if value < 0,
          do: {:error, {422, "данъчната ставка не може да е отрицателна"}},
          else: {:ok, Dec.text(value, 2)}
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

  defp required_date(value) do
    if String.trim(value || "") == "",
      do: {:error, {422, "decision_date е задължително"}},
      else: {:ok, value}
  end

  defp pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  defp pick_int(params, key, current) do
    case Params.integer(params, key) do
      nil -> current
      {:error, _} -> current
      value -> value
    end
  end

  defp string(params, key, default \\ "") do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end

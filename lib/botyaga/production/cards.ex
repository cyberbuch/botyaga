defmodule Botyaga.Production.Cards do
  @moduledoc """
  Месечна производствена карта (фактическо производство) — ръчният подход на
  CONTROLISY: материали от 601, преки разходи (602–609), дял от общи разходи,
  незавършено производство (начално/крайно салдо по 611) и разпределение между
  продуктите по количество×коефициент или ръчна сума.
  """

  import Ecto.Query

  alias Botyaga.{Attachments, Catalog, Dec, Journal, Params, Repo}
  alias Botyaga.Production.{Card, CardProduct, Order}

  def list(company_id) do
    Repo.all(from(c in Card, where: c.company_id == ^company_id, order_by: [desc: c.id]))
    |> Enum.map(&one(&1, false))
  end

  def get(company_id, id) do
    case Repo.get_by(Card, id: id, company_id: company_id) do
      nil -> {:error, {404, "картата не е намерена"}}
      c -> {:ok, one(c, true)}
    end
  end

  def create(company_id, params) do
    with {:ok, month} <- month_param(params) do
      {:ok, c} =
        Repo.insert(%Card{
          company_id: company_id,
          month: month,
          number: "ПК-#{month}",
          status: "draft",
          materials_account_id: account_by_prefix(company_id, "601"),
          production_account_id: account_by_prefix(company_id, "611"),
          kind: pick(params, "kind", "actual"),
          direct_accounts: Jason.encode!([]),
          common_accounts: Jason.encode!([]),
          notes: str(params, "notes")
        })

      insert_products(c.id, params)
      get(company_id, c.id)
    end
  end

  def update(company_id, id, params) do
    with {:ok, c} <- fetch_draft(company_id, id) do
      {:ok, c} =
        Repo.update(
          Ecto.Changeset.change(c,
            materials_account_id:
              pick_int(params, "materials_account_id", c.materials_account_id),
            production_account_id:
              pick_int(params, "production_account_id", c.production_account_id),
            direct_accounts: encode_ids(params, "direct_accounts", c.direct_accounts),
            common_accounts: encode_ids(params, "common_accounts", c.common_accounts),
            kind: pick(params, "kind", c.kind),
            common_share_percent: pick(params, "common_share_percent", c.common_share_percent),
            wip_end_mode: pick(params, "wip_end_mode", c.wip_end_mode),
            wip_end_value: pick(params, "wip_end_value", c.wip_end_value),
            notes: pick(params, "notes", c.notes)
          )
        )

      if Map.has_key?(params, "products") do
        Repo.delete_all(from(p in CardProduct, where: p.card_id == ^c.id))
        insert_products(c.id, params)
      end

      get(company_id, c.id)
    end
  end

  def delete(company_id, id) do
    with {:ok, c} <- fetch_draft(company_id, id) do
      Repo.delete!(c)
      Attachments.delete_for(company_id, "production_card", id)
      {:ok, nil}
    end
  end

  @doc "Преглед: събрани разходи, незавършено производство и разпределение по продукти."
  def preview(company_id, id) do
    with {:ok, c} <- fetch(company_id, id) do
      {:ok, compute(c)}
    end
  end

  def confirm(company_id, id) do
    with {:ok, c} <- fetch_draft(company_id, id),
         :ok <- accounts_present(c),
         pv = compute(c),
         :ok <- no_errors(pv),
         :ok <- has_products(pv) do
      sides = build_sides(company_id, c, pv)

      {:ok, eid} =
        Journal.write_entry(
          company_id,
          last_day(c.month),
          "production_card",
          c.id,
          c.number,
          "Месечно производство #{c.month}",
          0,
          "",
          c.month,
          sides
        )

      Repo.update!(Ecto.Changeset.change(c, status: "confirmed", journal_entry_id: eid))
      persist_costs(c, pv)
      get(company_id, id)
    end
  end

  def unpost(company_id, id) do
    with {:ok, c} <- fetch_confirmed(company_id, id) do
      Journal.wipe(c.journal_entry_id)
      Repo.update!(Ecto.Changeset.change(c, status: "draft", journal_entry_id: 0))
      get(company_id, id)
    end
  end

  ## Изчисление

  defp compute(c) do
    {products, materials} =
      if c.kind == "recipes" do
        {linked_orders(c), 0}
      else
        {products_of(c.id), month_total_prefix(c.company_id, c.month, "601")}
      end

    direct =
      ids(c.direct_accounts)
      |> Enum.map(fn aid ->
        %{account_id: aid, amount: month_total(c.company_id, c.month, aid)}
      end)
      |> Enum.filter(&(&1.amount != 0))

    common_total =
      ids(c.common_accounts) |> Enum.reduce(0, &(&2 + month_total(c.company_id, c.month, &1)))

    share_pct = Dec.or0(c.common_share_percent)
    common_share = Dec.div(Dec.mul(common_total, share_pct), 100 * Dec.scale()) || 0

    wip_begin = wip_begin(c.company_id, c.month, c.production_account_id)
    available = materials + Enum.reduce(direct, 0, &(&2 + &1.amount)) + common_share + wip_begin

    wip_end =
      case c.wip_end_mode do
        "percent" -> Dec.div(Dec.mul(available, Dec.or0(c.wip_end_value)), 100 * Dec.scale()) || 0
        _ -> Dec.or0(c.wip_end_value)
      end

    to_allocate = available - wip_end

    allocated = allocate(products, to_allocate)

    errors = []
    errors = if products == [], do: ["няма продукти в картата" | errors], else: errors

    errors =
      if to_allocate < 0,
        do: ["крайното незавършено надвишава наличните разходи" | errors],
        else: errors

    %{
      materials: Dec.money(materials),
      direct:
        Enum.map(direct, fn d -> %{account_id: d.account_id, amount: Dec.money(d.amount)} end),
      common_total: Dec.money(common_total),
      common_share: Dec.money(common_share),
      wip_begin: Dec.money(wip_begin),
      wip_end: Dec.money(wip_end),
      total: Dec.money(to_allocate),
      products: allocated,
      errors: errors
    }
  end

  # Закачени поръчки по рецепти: база за разпределение = тяхната себестойност.
  defp linked_orders(c) do
    Repo.all(
      from(o in Order,
        where: o.card_id == ^c.id and o.status == "completed",
        order_by: [asc: o.id]
      )
    )
    |> Enum.map(fn o ->
      out = Repo.get(Catalog.Product, o.output_product_id)

      %{
        id: o.id,
        product_id: o.output_product_id,
        quantity: o.quantity,
        coefficient: "1",
        manual_amount: "",
        weight: Dec.or0(o.material_cost),
        inventory_account_id: (out && out.inventory_account_id) || 0
      }
    end)
  end

  defp allocate(products, total) do
    manual = Enum.filter(products, &(&1.manual_amount != ""))
    auto = Enum.filter(products, &(&1.manual_amount == ""))

    manual_sum = Enum.reduce(manual, 0, &(&2 + Dec.or0(&1.manual_amount)))
    rest = total - manual_sum

    weight = fn p ->
      Map.get(p, :weight) || Dec.mul(Dec.or0(p.quantity), Dec.or0(p.coefficient))
    end

    total_weight = Enum.reduce(auto, 0, &(&2 + weight.(&1)))

    auto_costs =
      if total_weight > 0 do
        Enum.map(auto, fn p -> {p.id, Dec.div(Dec.mul(rest, weight.(p)), total_weight) || 0} end)
      else
        Enum.map(auto, fn p -> {p.id, 0} end)
      end

    # последният авто продукт поема остатъка от закръглянето
    auto_costs =
      case auto_costs do
        [] ->
          []

        list ->
          sum = Enum.reduce(list, 0, &(&2 + elem(&1, 1)))
          diff = rest - sum
          {lid, lv} = List.last(list)
          List.replace_at(list, length(list) - 1, {lid, lv + diff})
      end

    by_id = Map.new(auto_costs)

    Enum.map(products, fn p ->
      cost = if p.manual_amount != "", do: Dec.or0(p.manual_amount), else: Map.get(by_id, p.id, 0)

      %{
        id: p.id,
        product_id: p.product_id,
        name: product_name(p.product_id),
        quantity: p.quantity,
        coefficient: p.coefficient,
        manual_amount: p.manual_amount,
        inventory_account_id: p.inventory_account_id,
        cost: Dec.money(cost)
      }
    end)
  end

  defp build_sides(company_id, c, pv) do
    prod = account!(company_id, c.production_account_id)

    sides = []

    # Материалите (601xx, аналитични): Дт 611 общо / Кт всяка подсмекта с нейния оборот.
    sides =
      if Dec.or0(pv.materials) != 0 do
        credits =
          prefix_accounts(company_id, "601")
          |> Enum.map(fn a -> {a, month_total(company_id, c.month, a.id)} end)
          |> Enum.filter(fn {_a, v} -> v != 0 end)
          |> Enum.map(fn {a, v} -> %{account: a, direction: "credit", amount: Dec.money(v)} end)

        sides ++ [%{account: prod, direction: "debit", amount: pv.materials} | credits]
      else
        sides
      end

    sides =
      Enum.reduce(pv.direct, sides, fn d, acc ->
        a = account!(company_id, d.account_id)

        acc ++
          [
            %{account: prod, direction: "debit", amount: d.amount},
            %{account: a, direction: "credit", amount: d.amount}
          ]
      end)

    sides =
      if Dec.or0(pv.common_share) != 0 do
        common = ids(c.common_accounts)
        total = Enum.reduce(common, 0, &(&2 + month_total(company_id, c.month, &1)))

        Enum.reduce(common, sides, fn aid, acc ->
          amt = month_total(company_id, c.month, aid)

          part =
            if total > 0, do: Dec.div(Dec.mul(Dec.or0(pv.common_share), amt), total) || 0, else: 0

          if part != 0 do
            a = account!(company_id, aid)

            acc ++
              [
                %{account: prod, direction: "debit", amount: Dec.money(part)},
                %{account: a, direction: "credit", amount: Dec.money(part)}
              ]
          else
            acc
          end
        end)
      else
        sides
      end

    Enum.reduce(pv.products, sides, fn p, acc ->
      if Dec.or0(p.cost) != 0 do
        inv = account!(company_id, p.inventory_account_id)

        acc ++
          [
            %{account: inv, direction: "debit", amount: p.cost},
            %{account: prod, direction: "credit", amount: p.cost}
          ]
      else
        acc
      end
    end)
  end

  defp persist_costs(%{kind: "recipes"}, _pv), do: :ok

  defp persist_costs(_c, pv) do
    Enum.each(pv.products, fn p ->
      Repo.update_all(from(x in CardProduct, where: x.id == ^p.id), set: [cost: p.cost])
    end)
  end

  ## Събиране на разходи от дневника

  defp month_total(company_id, month, account_id) when account_id > 0 do
    rows =
      Repo.all(
        from(l in Journal.Line,
          join: e in Journal.Entry,
          on: l.entry_id == e.id,
          where:
            e.company_id == ^company_id and l.account_id == ^account_id and
              like(e.entry_date, ^"#{month}%"),
          select: {l.direction, l.amount}
        )
      )

    Enum.reduce(rows, 0, fn {dir, amt}, acc ->
      acc + if(dir == "debit", do: Dec.or0(amt), else: -Dec.or0(amt))
    end)
  end

  defp month_total(_company_id, _month, _account_id), do: 0

  defp wip_begin(company_id, month, account_id) when account_id > 0 do
    start = "#{month}-01"

    rows =
      Repo.all(
        from(l in Journal.Line,
          join: e in Journal.Entry,
          on: l.entry_id == e.id,
          where:
            e.company_id == ^company_id and l.account_id == ^account_id and e.entry_date < ^start,
          select: {l.direction, l.amount}
        )
      )

    Enum.reduce(rows, 0, fn {dir, amt}, acc ->
      acc + if(dir == "debit", do: Dec.or0(amt), else: -Dec.or0(amt))
    end)
  end

  defp wip_begin(_company_id, _month, _account_id), do: 0

  ## Вътрешни

  defp fetch(company_id, id), do: Repo.get_by(Card, id: id, company_id: company_id) |> ok404()

  defp fetch_draft(company_id, id) do
    with {:ok, c} <- fetch(company_id, id) do
      if c.status == "draft",
        do: {:ok, c},
        else: {:error, {422, "потвърдена карта не се променя"}}
    end
  end

  defp fetch_confirmed(company_id, id) do
    with {:ok, c} <- fetch(company_id, id) do
      if c.status == "confirmed", do: {:ok, c}, else: {:error, {422, "картата не е потвърдена"}}
    end
  end

  defp ok404(nil), do: {:error, {404, "картата не е намерена"}}
  defp ok404(c), do: {:ok, c}

  defp accounts_present(c) do
    cond do
      c.production_account_id <= 0 ->
        {:error, {422, "липсва сметка 611 (производство) — задайте я в сметкоплана"}}

      c.kind != "recipes" and c.materials_account_id <= 0 ->
        {:error, {422, "липсва сметка 601 (материали) — задайте я в сметкоплана"}}

      true ->
        :ok
    end
  end

  defp no_errors(%{errors: []}), do: :ok
  defp no_errors(_), do: {:error, {422, "прегледът има грешки"}}

  defp has_products(%{products: []}), do: {:error, {422, "няма продукти"}}
  defp has_products(_), do: :ok

  defp products_of(card_id),
    do: Repo.all(from(p in CardProduct, where: p.card_id == ^card_id, order_by: [asc: p.id]))

  defp insert_products(card_id, params) do
    arr = Map.get(params, "products") || []

    Enum.each(arr, fn p ->
      pid = Params.integer(p, "product_id") || 0
      product = Repo.get(Catalog.Product, pid)

      %CardProduct{}
      |> Ecto.Changeset.change(%{
        card_id: card_id,
        product_id: pid,
        quantity: pick(p, "quantity", "0"),
        coefficient: pick(p, "coefficient", "1"),
        manual_amount: pick(p, "manual_amount", ""),
        inventory_account_id: (product && product.inventory_account_id) || 0
      })
      |> Repo.insert!()
    end)
  end

  defp one(c, with_products) do
    base = %{
      id: c.id,
      number: c.number,
      month: c.month,
      status: c.status,
      materials_account_id: c.materials_account_id,
      production_account_id: c.production_account_id,
      direct_accounts: ids(c.direct_accounts),
      common_accounts: ids(c.common_accounts),
      kind: c.kind,
      common_share_percent: c.common_share_percent,
      wip_end_mode: c.wip_end_mode,
      wip_end_value: c.wip_end_value,
      journal_entry_id: c.journal_entry_id,
      notes: c.notes
    }

    if with_products do
      pv = compute(c)
      base |> Map.put(:products, pv.products) |> Map.put(:preview, Map.drop(pv, [:products]))
    else
      base
    end
  end

  defp ids(nil), do: []

  defp ids(json) do
    case Jason.decode(json || "[]") do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp encode_ids(params, key, current) do
    case Map.get(params, key) do
      list when is_list(list) -> Jason.encode!(list)
      _ -> current
    end
  end

  defp account_by_prefix(company_id, prefix) do
    q =
      from(a in Catalog.Account,
        where: a.company_id == ^company_id and like(a.number, ^"#{prefix}%"),
        order_by: [asc: a.number],
        limit: 1
      )

    case Repo.one(q) do
      nil -> 0
      a -> a.id
    end
  end

  defp month_total_prefix(company_id, month, prefix) do
    prefix_accounts(company_id, prefix)
    |> Enum.reduce(0, &(&2 + month_total(company_id, month, &1.id)))
  end

  defp prefix_accounts(company_id, prefix) do
    Repo.all(
      from(a in Catalog.Account,
        where: a.company_id == ^company_id and like(a.number, ^"#{prefix}%"),
        order_by: [asc: a.number]
      )
    )
  end

  defp account!(_company_id, id) do
    case Repo.get(Catalog.Account, id) do
      nil -> raise "липсва сметка #{id}"
      a -> a
    end
  end

  defp product_name(pid) do
    case Repo.get(Catalog.Product, pid) do
      nil -> ""
      p -> p.name
    end
  end

  defp month_param(params) do
    case str(params, "month") do
      m when byte_size(m) == 7 -> {:ok, m}
      _ -> {:error, {422, "month е задължителен (YYYY-MM)"}}
    end
  end

  defp last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    Date.to_iso8601(Date.end_of_month(Date.new!(y, m, 1)))
  end

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, v} -> v
      _ -> ""
    end
  end

  defp pick(params, key, default) do
    case str(params, key) do
      "" -> default
      v -> v
    end
  end

  defp pick_int(params, key, default) do
    case Params.integer(params, key) do
      nil -> default
      v -> v
    end
  end
end

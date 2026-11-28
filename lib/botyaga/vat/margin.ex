defmodule Botyaga.Vat.Margin do
  @moduledoc """
  Режим на облагане на маржа (чл.143–151 ЗДДС, чл.90 ППЗДС) за стоки втора
  употреба. ДДС се определя върху положителния марж по всяка стока поотделно
  (продажна − покупна цена); отрицателният марж е нула. Месечният протокол
  начислява ДДС (Дт 702 / Кт 4532) и влиза в дневника за продажбите с вид 09.
  """

  import Ecto.Query

  alias Botyaga.{Dec, Invoicing, Journal, Repo}
  alias Botyaga.Companies.Defaults
  alias Botyaga.Vat.{MarginProtocol, MarginProtocolLine}

  def list(company_id) do
    Repo.all(
      from(p in MarginProtocol, where: p.company_id == ^company_id, order_by: [desc: p.id])
    )
    |> Enum.map(&one(&1, false))
  end

  def get(company_id, id) do
    case Repo.get_by(MarginProtocol, id: id, company_id: company_id) do
      nil -> {:error, {404, "протоколът не е намерен"}}
      p -> {:ok, one(p, true)}
    end
  end

  @doc "Преглед „всичко или нищо“: марж по стока + проблеми."
  def preview(company_id, month) do
    sales = margin_sales(company_id, month)
    purchases = margin_purchases(company_id)

    {lines, errors} =
      Enum.reduce(sales, {[], []}, fn {pid, sale}, {acc, errs} ->
        purchase = Map.get(purchases, pid)

        if purchase == nil do
          {acc, ["стока #{pid}: няма осчетоводена покупка по маржа" | errs]}
        else
          margin = sale.net - purchase
          positive = max(margin, 0)
          export = sale.export == 1

          {vat, base} =
            if export,
              do: {0, positive},
              else:
                {Dec.div(Dec.mul(positive, 20), 120) || 0,
                 positive - (Dec.div(Dec.mul(positive, 20), 120) || 0)}

          line = %{
            product_id: pid,
            sale_invoice_id: sale.inv_id,
            purchase_price: Dec.money(purchase),
            sale_price: Dec.money(sale.net),
            margin: Dec.money(margin),
            base: Dec.money(base),
            vat: Dec.money(vat),
            export: sale.export
          }

          {acc ++ [line], errs}
        end
      end)

    {:ok,
     %{
       lines: lines,
       errors: Enum.reverse(errors),
       total_base: sum(lines, & &1.base),
       total_vat: sum(lines, & &1.vat)
     }}
  end

  def create(company_id, month) do
    with :ok <- month_free(company_id, month),
         {:ok, pv} <- preview(company_id, month),
         :ok <- no_errors(pv) do
      {:ok, p} =
        Repo.transaction(fn ->
          p =
            Repo.insert!(%MarginProtocol{
              company_id: company_id,
              month: month,
              status: "confirmed",
              total_base: pv.total_base,
              total_vat: pv.total_vat
            })

          p = Repo.update!(Ecto.Changeset.change(p, number: "МАРЖ-#{month}"))
          insert_lines(p.id, pv.lines)

          eid = write_entry(company_id, p, pv.lines)
          Repo.update!(Ecto.Changeset.change(p, journal_entry_id: eid))
          p
        end)

      get(company_id, p.id)
    end
  end

  def delete(company_id, id) do
    with {:ok, p} <- get(company_id, id) do
      Journal.wipe(p.journal_entry_id)
      Repo.delete!(p)
      {:ok, nil}
    end
  end

  ## Дневник за продажбите: редове на протокола (вид 09)

  @doc "Редове за дневника: {base, vat, export} по стока за месеца."
  def journal_rows(company_id, month) do
    case Repo.get_by(MarginProtocol, company_id: company_id, month: month, status: "confirmed") do
      nil ->
        []

      p ->
        Repo.all(
          from(l in MarginProtocolLine, where: l.protocol_id == ^p.id, order_by: [asc: l.id])
        )
        |> Enum.map(fn l ->
          %{
            base: Kernel.div(Dec.or0(l.base), 10_000),
            vat: Kernel.div(Dec.or0(l.vat), 10_000),
            export: l.export,
            product_id: l.product_id
          }
        end)
    end
  end

  ## Вътрешни

  defp margin_sales(company_id, month) do
    Repo.all(
      from(i in Invoicing.Invoice,
        where:
          i.company_id == ^company_id and i.is_margin == 1 and i.direction == "out" and
            i.status == "posted" and like(i.issue_date, ^"#{month}%"),
        order_by: [asc: i.id]
      )
    )
    |> Enum.reduce(%{}, fn i, acc ->
      lines = Invoicing.lines_of(i.id)

      Enum.reduce(lines, acc, fn l, a ->
        pid = l.product_id
        cur = Map.get(a, pid, %{net: 0, export: i.margin_export, inv_id: i.id})
        Map.put(a, pid, %{cur | net: cur.net + (Dec.or0(l.net_amount) || 0)})
      end)
    end)
  end

  defp margin_purchases(company_id) do
    all =
      Repo.all(
        from(i in Invoicing.Invoice,
          where:
            i.company_id == ^company_id and i.is_margin == 1 and i.direction == "in" and
              i.status == "posted",
          order_by: [asc: i.id]
        )
      )
      |> Enum.reduce(%{}, fn i, acc ->
        lines = Invoicing.lines_of(i.id)

        Enum.reduce(lines, acc, fn l, a ->
          Map.update(
            a,
            l.product_id,
            Dec.or0(l.net_amount) || 0,
            &(&1 + (Dec.or0(l.net_amount) || 0))
          )
        end)
      end)

    # Покупките, вече „изразходени“ в потвърдени протоколи, не се броят повторно —
    # иначе един и същ марж се приспада в два различни месеца.
    consumed =
      Repo.all(
        from(l in MarginProtocolLine,
          join: p in MarginProtocol,
          on: p.id == l.protocol_id,
          where: p.company_id == ^company_id and p.status == "confirmed",
          select: {l.product_id, l.purchase_price}
        )
      )
      |> Enum.reduce(%{}, fn {pid, price}, acc ->
        Map.update(acc, pid, Dec.or0(price) || 0, &(&1 + (Dec.or0(price) || 0)))
      end)

    Map.merge(all, consumed, fn _pid, total, used -> max(total - used, 0) end)
  end

  defp write_entry(company_id, p, lines) do
    with {:ok, rev} <-
           Defaults.resolve(Repo.get(Botyaga.Companies.Company, company_id), "revenues"),
         {:ok, vat} <-
           Defaults.resolve(Repo.get(Botyaga.Companies.Company, company_id), "vat_sale") do
      sides =
        Enum.flat_map(lines, fn l ->
          v = Dec.or0(l.vat)

          if v != 0,
            do: [
              %{account: rev, direction: "debit", amount: Dec.money(v)},
              %{account: vat, direction: "credit", amount: Dec.money(v)}
            ],
            else: []
        end)

      if sides == [] do
        0
      else
        {:ok, eid} =
          Journal.write_entry(
            company_id,
            last_day(p.month),
            "margin_protocol",
            p.id,
            p.number,
            "Протокол чл.90 марж #{p.month}",
            0,
            "",
            p.month,
            sides
          )

        eid
      end
    else
      _ -> 0
    end
  end

  defp insert_lines(protocol_id, lines) do
    Enum.each(lines, fn l ->
      %MarginProtocolLine{}
      |> Ecto.Changeset.change(%{
        protocol_id: protocol_id,
        product_id: l.product_id,
        sale_invoice_id: l.sale_invoice_id,
        purchase_price: l.purchase_price,
        sale_price: l.sale_price,
        margin: l.margin,
        base: l.base,
        vat: l.vat,
        export: l.export
      })
      |> Repo.insert!()
    end)
  end

  defp month_free(company_id, month) do
    if Repo.get_by(MarginProtocol, company_id: company_id, month: month),
      do: {:error, {422, "вече има протокол за маржа за този месец — изтрийте го първо"}},
      else: :ok
  end

  defp no_errors(%{errors: []}), do: :ok
  defp no_errors(_), do: {:error, {422, "прегледът има проблеми — поправете ги преди създаване"}}

  defp sum(lines, fun), do: Enum.reduce(lines, 0, &(&2 + Dec.or0(fun.(&1)))) |> Dec.money()

  defp last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    Date.to_iso8601(Date.end_of_month(Date.new!(y, m, 1)))
  end

  defp one(p, with_lines) do
    base = %{
      id: p.id,
      month: p.month,
      number: p.number,
      status: p.status,
      journal_entry_id: p.journal_entry_id,
      total_base: p.total_base,
      total_vat: p.total_vat
    }

    if with_lines do
      lines =
        Repo.all(
          from(l in MarginProtocolLine, where: l.protocol_id == ^p.id, order_by: [asc: l.id])
        )
        |> Enum.map(fn l ->
          %{
            product_id: l.product_id,
            purchase_price: l.purchase_price,
            sale_price: l.sale_price,
            margin: l.margin,
            base: l.base,
            vat: l.vat,
            export: l.export
          }
        end)

      Map.put(base, :lines, lines)
    else
      base
    end
  end
end

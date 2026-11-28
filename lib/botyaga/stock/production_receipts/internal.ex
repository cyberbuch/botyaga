defmodule Botyaga.Stock.ProductionReceipts.Internal do
  @moduledoc """
  Вътрешни помощни функции на ръчния приход на продукция: зареждане на
  документа, JSON изгледи, валидации и четене на параметри.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Dec, Params, Repo}
  alias Botyaga.Catalog.Account

  alias Botyaga.Stock.{
    ProductionReceipt,
    ProductionReceiptAllocation,
    ProductionReceiptLine
  }

  @doc_type "production_receipt"

  ## Вътрешни

  def fetch(company_id, id) do
    id = Params.id(id)

    if id <= 0 do
      {:error, {400, "invalid id"}}
    else
      case Repo.get_by(ProductionReceipt, id: id, company_id: company_id) do
        nil -> {:error, {404, "документът не е намерен"}}
        doc -> {:ok, doc}
      end
    end
  end

  def with_audit(company_id, doc) do
    one(doc, true)
    |> Audit.attach_stamp(Map.get(Audit.stamps_for(company_id, @doc_type), doc.id))
    |> Map.put(:audit_history, Audit.history_for(company_id, @doc_type, doc.id))
  end

  def one(doc, with_lines) do
    base = %{
      id: doc.id,
      number: doc.number,
      doc_date: doc.doc_date,
      month: doc.month,
      status: doc.status,
      notes: doc.notes,
      journal_entry_id: doc.journal_entry_id,
      wip_end_mode: doc.wip_end_mode,
      wip_end_value: doc.wip_end_value
    }

    if with_lines do
      base
      |> Map.put(:lines, lines_json(doc.id))
      |> Map.put(:allocations, allocations_json(doc.id))
    else
      base
    end
  end

  def lines_of(doc_id) do
    Repo.all(
      from(l in ProductionReceiptLine,
        where: l.doc_id == ^doc_id,
        order_by: [asc: l.line_no, asc: l.id]
      )
    )
  end

  def lines_json(doc_id) do
    lines_of(doc_id)
    |> Enum.map(fn l ->
      %{
        id: l.id,
        line_no: l.line_no,
        product_id: l.product_id,
        sold_quantity: l.sold_quantity,
        sold_amount: l.sold_amount,
        ending_quantity: l.ending_quantity,
        quantity: l.quantity,
        unit_cost: l.unit_cost,
        amount: l.amount,
        allocated_amount: l.allocated_amount,
        writeoff_amount: l.writeoff_amount,
        inventory_account_id: l.inventory_account_id,
        revenue_account_id: l.revenue_account_id,
        expense_account_id: l.expense_account_id,
        coefficient: l.coefficient,
        manual_amount: l.manual_amount
      }
    end)
  end

  def allocations_json(doc_id) do
    Repo.all(
      from(a in ProductionReceiptAllocation,
        where: a.doc_id == ^doc_id,
        order_by: [asc: a.line_no, asc: a.id]
      )
    )
    |> Enum.map(fn a ->
      %{
        id: a.id,
        line_no: a.line_no,
        product_id: a.product_id,
        account_id: a.account_id,
        base_amount: a.base_amount,
        amount: a.amount
      }
    end)
  end

  def doc_total(value) do
    value
    |> Map.get(:lines, [])
    |> Enum.reduce(0, fn l, sum -> sum + Dec.or0(l.amount) end)
    |> Dec.money()
  end

  def no_other_confirmed(company_id, doc) do
    exists =
      Repo.exists?(
        from(d in ProductionReceipt,
          where:
            d.company_id == ^company_id and d.month == ^doc.month and d.status == "confirmed" and
              d.id != ^doc.id
        )
      )

    if exists do
      {:error, {409, "вече има потвърден приход на продукция за #{doc.month}"}}
    else
      :ok
    end
  end

  def lines_ready(company_id, lines) do
    case Enum.reduce_while(lines, :ok, fn l, _acc ->
           cond do
             l.inventory_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 303"}}}

             l.revenue_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 701"}}}

             l.expense_account_id <= 0 ->
               {:halt, {:error, {422, "ред без сметка 611"}}}

             Dec.or0(l.quantity) < 0 ->
               {:halt, {:error, {422, "отрицателно произведено количество"}}}

             true ->
               {:cont, :ok}
           end
         end) do
      :ok -> account_refs_ok(company_id, lines)
      err -> err
    end
  end

  def account_refs_ok(company_id, lines) do
    ids =
      Enum.flat_map(
        lines,
        &[&1.inventory_account_id, &1.revenue_account_id, &1.expense_account_id]
      )
      |> Enum.uniq()

    if Enum.all?(ids, &(Repo.get_by(Account, id: &1, company_id: company_id) != nil)) do
      :ok
    else
      {:error, {422, "липсва сметка от артикула"}}
    end
  end

  def not_empty([]), do: {:error, {422, "документът няма редове"}}
  def not_empty(_), do: :ok

  def draft(%ProductionReceipt{status: "draft"}), do: :ok
  def draft(_), do: {:error, {409, "потвърден документ не се променя"}}

  def confirmed(%ProductionReceipt{status: "confirmed"}), do: :ok
  def confirmed(_), do: {:error, {422, "документът не е потвърден"}}

  def month_param(params) do
    case Params.str(params, "month") do
      {:present, m} ->
        m = String.trim(m)

        case String.split(m, "-") do
          [y, mo] ->
            with {_yi, ""} <- Integer.parse(y),
                 {mi, ""} <- Integer.parse(mo),
                 true <- mi in 1..12 do
              {:ok, m}
            else
              _ -> {:error, {422, "месецът е YYYY-MM"}}
            end

          _ ->
            {:error, {422, "месецът е YYYY-MM"}}
        end

      _ ->
        {:error, {422, "месецът е задължителен (YYYY-MM)"}}
    end
  end

  def prefix(params, key, default) do
    case Params.str(params, key) do
      {:present, v} ->
        v = String.trim(v)
        if v == "", do: default, else: v

      _ ->
        default
    end
  end

  def last_day(month) do
    [y, m] = String.split(month, "-") |> Enum.map(&String.to_integer/1)
    days = Date.days_in_month(Date.new!(y, m, 1))
    "#{month}-#{String.pad_leading(Integer.to_string(days), 2, "0")}"
  end

  def qty_of(raw) do
    case Dec.parse(raw) do
      nil -> {:error, {422, "невалидно количество"}}
      value when value >= 0 -> {:ok, value}
      _ -> {:error, {422, "отрицателно количество"}}
    end
  end

  def pick(params, key, current) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> current
    end
  end

  def string(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

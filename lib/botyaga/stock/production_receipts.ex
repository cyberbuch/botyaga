defmodule Botyaga.Stock.ProductionReceipts do
  @moduledoc """
  Ръчен приход на продукция за месец (производство по поръчка — без рецепта).

  Таб 1 "Произведено": продаденото по КТ 701 за месеца (фактури за продажба),
  натрупаната стойност в 611 (себестойност на продаденото) и ръчно поле
  „наличност" в края на месеца — произведено = продадено + наличност.
  Таб 2 "Разпределение 612": натрупаните непреки разходи по 612 (без 61201)
  се разпределят пропорционално на произведената стойност по артикул.
  Таб 3 "Записи": при потвърждаване се пише един запис —
  ДТ 303 КТ 611 (приход на продукция), ДТ 303 КТ 612 (разпределение) и
  ДТ 701 КТ 303 за продаденото (в 303 вече е пълната стойност).

  Сметките се вземат от артикула: 303 = inventory_account_id,
  701 = revenue_account_id, 611 = expense_account_id. Префиксите 611/612
  в прегледа са параметри (по подразбиране "611"/"612", изключва се "61201").

  Подмодули: `Lines` (таб 1 и редове на документа), `Alloc` (таб 2 —
  разпределение по 612), `Journal` (таб 3 — journal запис) и `Internal`
  (вътрешни помощни функции).
  """

  import Ecto.Query

  alias Botyaga.{Attachments, Audit, Dec, Journal, Periods, Repo}

  alias Botyaga.Stock.{
    ProductionReceipt,
    ProductionReceiptAllocation,
    ProductionReceiptLine
  }

  alias Botyaga.Stock.ProductionReceipts.{Alloc, Internal, Lines}
  alias Botyaga.Stock.ProductionReceipts.Journal, as: ReceiptJournal

  @doc_type "production_receipt"

  ## Списък и преглед

  def index(company_id) do
    stamps = Audit.stamps_for(company_id, @doc_type)

    Repo.all(
      from(d in ProductionReceipt, where: d.company_id == ^company_id, order_by: [desc: d.id])
    )
    |> Enum.map(fn d -> d |> Internal.one(false) |> Audit.attach_stamp(Map.get(stamps, d.id)) end)
  end

  def show(company_id, id) do
    with {:ok, doc} <- Internal.fetch(company_id, id) do
      {:ok, Internal.with_audit(company_id, doc)}
    end
  end

  @doc """
  Таб 1 преди създаване: продаденото по КТ 701 за месеца, натрупаната
  стойност в 611 и натрупаните непреки разходи по 612 за разпределение.
  """
  def preview(company_id, params) do
    with {:ok, month} <- Internal.month_param(params) do
      products = Lines.products_map(company_id)
      sold = Lines.sold_by_product(company_id, month, products)
      expense_total = Lines.expense_total(company_id, month, params)
      total_sold = sold |> Enum.reduce(0, fn {_pid, s}, acc -> acc + s.qty end)
      unit = if total_sold > 0, do: Dec.div(expense_total, total_sold) || 0, else: 0

      lines =
        sold
        |> Enum.map(fn {pid, %{qty: q, revenue: rev}} ->
          p = Map.fetch!(products, pid)

          %{
            product_id: pid,
            product_name: p.name,
            code: p.code,
            unit: p.unit,
            sold_quantity: Dec.qty(q),
            sold_revenue: Dec.money(rev),
            sold_amount: Dec.money(Dec.mul(q, unit)),
            unit_cost: Dec.text(unit, 6),
            inventory_account_id: p.inventory_account_id,
            revenue_account_id: p.revenue_account_id,
            expense_account_id: Lines.expense_account(company_id, p)
          }
        end)
        |> Enum.sort_by(& &1.product_name)

      %{
        month: month,
        doc_date: Internal.last_day(month),
        lines: lines,
        expense_total: Dec.money(expense_total),
        expense_turnover:
          Alloc.turnover(company_id, month, Internal.prefix(params, "expense_prefix", "611"), ""),
        indirect: Alloc.indirect_json(company_id, month, params)
      }
      |> then(&{:ok, &1})
    end
  end

  ## CRUD

  def create(company_id, sub, params) do
    with {:ok, month} <- Internal.month_param(params),
         {:ok, lines} <- Lines.build_lines(company_id, month, params) do
      date = Internal.last_day(month)
      notes = Internal.string(params, "notes")

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.insert!(%ProductionReceipt{
              company_id: company_id,
              doc_date: date,
              month: month,
              status: "draft",
              notes: notes,
              journal_entry_id: 0,
              wip_end_mode: Internal.pick(params, "wip_end_mode", "amount"),
              wip_end_value: Internal.pick(params, "wip_end_value", "0")
            })

          doc = Repo.update!(Ecto.Changeset.change(doc, number: "ПР-#{doc.id}"))
          Lines.insert_lines(doc.id, lines)
          doc
        end)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "create",
        "Създаден ръчен приход на продукция #{doc.number} за #{month}",
        "",
        "0.00",
        nil,
        Internal.one(doc, true)
      )

      show(company_id, doc.id)
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, doc} <- Internal.fetch(company_id, id),
         :ok <- Internal.draft(doc),
         {:ok, lines} <- Lines.build_lines(company_id, doc.month, params) do
      notes = Internal.pick(params, "notes", doc.notes)
      before = Internal.one(doc, true)

      {:ok, doc} =
        Repo.transaction(fn ->
          doc =
            Repo.update!(
              Ecto.Changeset.change(doc,
                notes: notes,
                wip_end_mode: Internal.pick(params, "wip_end_mode", doc.wip_end_mode),
                wip_end_value: Internal.pick(params, "wip_end_value", doc.wip_end_value)
              )
            )

          Repo.delete_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id))
          Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))
          Lines.insert_lines(doc.id, lines)
          doc
        end)

      after_value = Internal.one(doc, true)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "update",
        "Редактиран ръчен приход на продукция #{doc.number} за #{doc.month}",
        Internal.doc_total(before),
        Internal.doc_total(after_value),
        before,
        after_value
      )

      show(company_id, doc.id)
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, doc} <- Internal.fetch(company_id, id),
         :ok <- Internal.draft(doc) do
      before = Internal.one(doc, true)
      Repo.delete_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id))
      Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))
      Repo.delete!(doc)
      Attachments.delete_for(company_id, "production_receipt", id)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        doc.id,
        doc.number,
        "delete",
        "Изтрит ръчен приход на продукция #{doc.number} за #{doc.month}",
        Internal.doc_total(before),
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  ## Потвърждаване / връщане

  def confirm(company_id, sub, id) do
    with {:ok, doc} <- Internal.fetch(company_id, id),
         :ok <- Internal.draft(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date),
         :ok <- Internal.no_other_confirmed(company_id, doc),
         lines = Internal.lines_of(doc.id),
         :ok <- Internal.not_empty(lines),
         :ok <- Internal.lines_ready(company_id, lines),
         recomputed = Lines.recompute_lines(company_id, doc.month, lines, doc),
         :ok <- ReceiptJournal.values_present(recomputed),
         {:ok, allocs, indirect_total} <-
           Alloc.allocations(company_id, doc.month, recomputed, %{}),
         {:ok, sides, totals} <-
           ReceiptJournal.sides(company_id, recomputed, allocs, indirect_total) do
      {:ok, _entry_id} =
        Repo.transaction(fn ->
          entry_id =
            if sides == [] do
              0
            else
              {:ok, eid} =
                Journal.write_entry(
                  company_id,
                  doc.doc_date,
                  @doc_type,
                  doc.id,
                  doc.number,
                  "Ръчен приход на продукция #{doc.month} (#{doc.number})",
                  0,
                  "",
                  doc.month,
                  sides
                )

              eid
            end

          ReceiptJournal.persist_lines(doc.id, recomputed, allocs)
          ReceiptJournal.insert_allocations(doc.id, allocs)

          Repo.update!(
            Ecto.Changeset.change(doc, status: "confirmed", journal_entry_id: entry_id)
          )

          entry_id
        end)

      {:ok, after_doc} = Internal.fetch(company_id, id)
      after_value = Internal.one(after_doc, true)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        after_doc.number,
        "post",
        "Потвърден ръчен приход на продукция #{after_doc.number} за #{doc.month}, сума #{totals.total}",
        "0.00",
        totals.total,
        Internal.one(doc, true),
        after_value
      )

      {:ok, Internal.with_audit(company_id, after_doc)}
    end
  end

  def unpost(company_id, sub, id) do
    with {:ok, doc} <- Internal.fetch(company_id, id),
         :ok <- Internal.confirmed(doc),
         :ok <- Periods.assert_open(company_id, doc.doc_date) do
      before = Internal.one(doc, true)
      old_tot = Internal.doc_total(before)
      Journal.wipe(doc.journal_entry_id)

      Repo.transaction(fn ->
        Repo.delete_all(from(a in ProductionReceiptAllocation, where: a.doc_id == ^doc.id))

        Repo.update_all(from(l in ProductionReceiptLine, where: l.doc_id == ^doc.id),
          set: [allocated_amount: "0.00", writeoff_amount: "0.00"]
        )

        Repo.update!(Ecto.Changeset.change(doc, status: "draft", journal_entry_id: 0))
      end)

      {:ok, after_doc} = Internal.fetch(company_id, id)

      Audit.record(
        company_id,
        sub,
        @doc_type,
        id,
        after_doc.number,
        "unpost",
        "Върнат в чернова ръчен приход #{after_doc.number} за #{doc.month}, стара сума #{old_tot}",
        old_tot,
        "0.00",
        before,
        Internal.one(after_doc, true)
      )

      {:ok, Internal.with_audit(company_id, after_doc)}
    end
  end
end

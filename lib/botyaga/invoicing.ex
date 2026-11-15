defmodule Botyaga.Invoicing do
  @moduledoc """
  Фактури: чернови, номера, редакции и триене. Постът е в `Invoicing.Post`,
  четенето в `Invoicing.Read`, редовете в `Invoicing.Lines`.
  Всички записи на фактура с редовете ѝ са в една транзакция.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Journal, Params, Repo}
  alias Botyaga.Invoicing.{Head, Invoice, InvoiceLine, Lines, Money, Read}
  alias Botyaga.Companies.Series

  def list(company_id), do: Read.list(company_id)
  def detail(company_id, sub, id), do: Read.detail(company_id, sub, id)

  def create(company_id, sub, params) do
    with {:ok, head, lines} <- Head.from_create(params),
         {:ok, head} <- with_number(head, company_id),
         :ok <- check_in_duplicate(company_id, head, 0),
         {:ok, name} <- Lines.prepare(company_id, head, 0),
         :ok <- Lines.ensure_products(company_id, lines) do
      {:ok, inv} =
        Repo.transaction(fn ->
          {net, vat, total} = Lines.totals(head, lines)

          inv =
            Repo.insert!(%Invoice{
              company_id: company_id,
              direction: head.direction,
              document_type: head.document_type,
              number: head.number,
              issue_date: head.issue_date,
              due_date: head.due_date,
              counterpart_id: head.counterpart_id,
              counterpart_name: name,
              currency: head.currency,
              net_amount: net,
              vat_amount: vat,
              total_amount: total,
              status: "draft",
              payment_method: head.payment_method,
              notes: head.notes,
              tax_event_date: head.tax_event_date,
              accounting_month: head.accounting_month,
              currency_rate: head.currency_rate,
              discount_percent: head.discount_percent,
              discount_amount: head.discount_amount,
              vat_exemption_reason: head.vat_exemption_reason,
              original_invoice_id: head.original_invoice_id,
              location_id: head.location_id,
              journal_entry_id: 0,
              exclude_vat: head.exclude_vat,
              vat_article: head.vat_article,
              customs_statistical: head.customs_statistical,
              customs_duty: head.customs_duty,
              customs_vat: head.customs_vat
            })

          Lines.insert_lines(inv.id, company_id, lines)
          inv
        end)

      {:ok, after_value} = Read.detail(company_id, sub, inv.id)
      total = Map.get(after_value, :total_amount, "0.00")
      curr = Map.get(after_value, :currency, "EUR")
      dir_bg = if head.direction == "in", do: "входящ", else: "изходящ"

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        head.number,
        "create",
        "Създаден #{dir_bg} документ (#{Money.title(head.document_type)}) № #{head.number} — #{name}, сума #{total} #{curr}",
        "",
        "#{total} #{curr}",
        nil,
        after_value
      )

      Read.detail(company_id, sub, inv.id)
    end
  end

  def update(company_id, sub, id, params) do
    with {:ok, inv} <- fetch(company_id, id),
         :ok <- editable(inv),
         {:ok, head, lines} <- Head.overlay(Read.head_of(inv), params),
         {:ok, head} <- with_number_update(head, company_id),
         :ok <- check_in_duplicate(company_id, head, inv.id),
         {:ok, name} <- Lines.prepare(company_id, head, inv.id),
         :ok <- Lines.ensure_products(company_id, lines) do
      before = Read.value(inv, true)

      {:ok, inv} =
        Repo.transaction(fn ->
          inv =
            Repo.update!(
              Ecto.Changeset.change(inv,
                direction: head.direction,
                document_type: head.document_type,
                number: head.number,
                issue_date: head.issue_date,
                due_date: head.due_date,
                counterpart_id: head.counterpart_id,
                counterpart_name: name,
                currency: head.currency,
                payment_method: head.payment_method,
                notes: head.notes,
                tax_event_date: head.tax_event_date,
                accounting_month: head.accounting_month,
                currency_rate: head.currency_rate,
                discount_percent: head.discount_percent,
                discount_amount: head.discount_amount,
                vat_exemption_reason: head.vat_exemption_reason,
                original_invoice_id: head.original_invoice_id,
                location_id: head.location_id,
                exclude_vat: head.exclude_vat,
                vat_article: head.vat_article,
                customs_statistical: head.customs_statistical,
                customs_duty: head.customs_duty,
                customs_vat: head.customs_vat
              )
            )

          inv =
            if lines do
              Lines.replace_lines(inv.id, company_id, lines)
              {net, vat, total} = Lines.totals(head, lines)

              Repo.update!(
                Ecto.Changeset.change(inv, net_amount: net, vat_amount: vat, total_amount: total)
              )
            else
              inv
            end

          if head.document_type == "07" and String.trim(head.customs_statistical) != "" do
            s = Money.cents(head.customs_statistical) || 0
            d = Money.cents(head.customs_duty) || 0
            v = Money.cents(head.customs_vat) || 0

            Repo.update!(
              Ecto.Changeset.change(inv,
                net_amount: Money.money(s + d),
                vat_amount: Money.money(v),
                total_amount: Money.money(s + d + v)
              )
            )
          else
            inv
          end
        end)

      {:ok, after_value} = Read.detail(company_id, sub, inv.id)
      old_total = "#{inv.total_amount} #{inv.currency}"

      new_total =
        "#{Map.get(after_value, :total_amount, "0.00")} #{Map.get(after_value, :currency, "EUR")}"

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        head.number,
        "update",
        "Редактиран документ (#{Money.title(head.document_type)}) № #{head.number} — #{name}",
        old_total,
        new_total,
        before,
        after_value
      )

      Read.detail(company_id, sub, inv.id)
    end
  end

  def delete(company_id, sub, id) do
    with {:ok, inv} <- fetch(company_id, id) do
      before = Read.value(inv, true)
      old_total = "#{inv.total_amount} #{inv.currency}"
      delete_one(inv)

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        inv.number,
        "delete",
        "Изтрит документ (#{Money.title(inv.document_type)}) № #{inv.number} — #{inv.counterpart_name}, сума #{old_total}",
        old_total,
        "",
        before,
        nil
      )

      {:ok, nil}
    end
  end

  def bulk_delete(company_id, sub, ids) do
    {done, failed, results} =
      Enum.reduce(ids, {0, 0, []}, fn id, {done, failed, results} ->
        case delete(company_id, sub, id) do
          {:ok, nil} ->
            {done + 1, failed, results ++ [%{id: id, ok: 1}]}

          {:error, {_status, detail}} ->
            {done, failed + 1, results ++ [%{id: id, ok: 0, error: detail}]}
        end
      end)

    %{deleted: done, failed: failed, results: results}
  end

  def next_number(company_id, params) do
    direction = params |> Map.get("direction", "out") |> to_string() |> String.trim()
    direction = if direction == "", do: "out", else: direction

    if direction not in ["in", "out"] do
      {:error, {422, "direction must be 'in' or 'out'"}}
    else
      doc_type = params |> Map.get("document_type", "01") |> to_string() |> String.trim()
      doc_type = if doc_type == "", do: "01", else: doc_type

      number =
        if direction == "out" or doc_type == "09", do: next_out(company_id, doc_type), else: ""

      {:ok, %{number: number, document_type: doc_type, direction: direction}}
    end
  end

  @doc "Следващ номер от серията за този вид документ."
  def next_out(company_id, doc_type) do
    series =
      Repo.all(from(s in Series, where: s.company_id == ^company_id, order_by: [asc: s.id]))

    {types, pad, start} =
      Enum.find_value(series, {doc_type, 10, 1}, fn s ->
        if csv_has(s.document_types, doc_type),
          do: {s.document_types, s.pad_width, s.start_number}
      end)

    pad = if pad <= 0, do: 10, else: pad
    start = if start <= 0, do: 1, else: start

    numbers =
      Repo.all(
        from(i in Invoice,
          where:
            i.company_id == ^company_id and (i.direction == "out" or i.document_type == "09"),
          select: {i.document_type, i.number}
        )
      )

    base =
      numbers
      |> Enum.filter(fn {type, _number} -> csv_has(types, type) end)
      |> Enum.map(fn {_type, number} -> to_int(number) end)
      |> Enum.max(fn -> max(start - 1, 0) end)

    pad_num(base + 1, pad)
  end

  def load(id), do: Repo.get(Invoice, Params.id(id))

  def fetch(company_id, id) do
    case load(id) do
      nil ->
        {:error, {404, "фактурата не е намерена"}}

      inv ->
        if inv.company_id == company_id,
          do: {:ok, inv},
          else: {:error, {404, "фактурата не е намерена"}}
    end
  end

  def delete_one(inv) do
    Repo.transaction(fn ->
      Enum.each(journal_ids(inv), &Journal.wipe/1)
      Repo.delete_all(from(l in InvoiceLine, where: l.invoice_id == ^inv.id))
      Repo.delete!(inv)
    end)

    :ok
  end

  def journal_ids(inv) do
    ids = if inv.journal_entry_id > 0, do: [inv.journal_entry_id], else: []

    others =
      Repo.all(
        from(e in Journal.Entry,
          where: e.document_id == ^inv.id and e.document_type == ^inv.document_type,
          select: e.id
        )
      )

    Enum.uniq(ids ++ others)
  end

  def lines_of(invoice_id) do
    Repo.all(from(l in InvoiceLine, where: l.invoice_id == ^invoice_id, order_by: [asc: l.id]))
  end

  defp editable(%Invoice{status: "posted"}),
    do: {:error, {409, "фактурата е осчетоводена — първо я върни към чернова"}}

  defp editable(_), do: :ok

  defp with_number(head, company_id) do
    if head.number == "",
      do: {:ok, %{head | number: next_out(company_id, head.document_type)}},
      else: {:ok, head}
  end

  defp with_number_update(head, company_id) do
    if (head.direction == "out" or head.document_type == "09") and head.number == "" do
      {:ok, %{head | number: next_out(company_id, head.document_type)}}
    else
      {:ok, head}
    end
  end

  defp check_in_duplicate(company_id, head, exclude_id) do
    if head.direction != "in" or String.trim(head.number) == "" or head.counterpart_id <= 0 do
      :ok
    else
      numbers =
        Repo.all(
          from(i in Invoice,
            where:
              i.company_id == ^company_id and i.direction == "in" and
                i.counterpart_id == ^head.counterpart_id and i.id != ^exclude_id,
            select: i.number
          )
        )

      want = String.downcase(String.trim(head.number))

      if Enum.any?(numbers, fn number -> String.downcase(String.trim(number || "")) == want end) do
        {:error, {409, "входящ документ с този номер от този доставчик вече съществува"}}
      else
        :ok
      end
    end
  end

  defp csv_has(csv, needle) do
    (csv || "") |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.member?(needle)
  end

  defp pad_num(number, width) do
    width = width |> max(1) |> min(10)
    number |> max(0) |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp to_int(nil), do: 0

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> 0
    end
  end
end

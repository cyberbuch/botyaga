defmodule Botyaga.Invoicing.Special do
  @moduledoc """
  Протокол по чл. 117 от ЗДДС (09) и Митническа декларация (07) към входяща
  фактура — без директно отразяване в ДДС дневниците.
  """

  alias Botyaga.{Audit, Invoicing}
  alias Botyaga.Invoicing.{Head, Lines, Money, Read}

  def issue_protocol(company_id, sub, id, params) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         :ok <- incoming(inv, "протокол по чл. 117 се издава само към входяща фактура") do
      article = default(params, "vat_article", "чл. 117")
      rate_c = Money.cents(default(params, "vat_rate", "20")) || 2000
      rate_str = Money.money(rate_c)
      issue_date = default(params, "issue_date", inv.issue_date)
      number = default(params, "number", "")
      number = if number == "", do: Invoicing.next_out(company_id, "09"), else: number

      src_lines = Invoicing.lines_of(inv.id)

      new_lines =
        if src_lines == [] do
          net_c = Money.cents(inv.net_amount) || 0
          vat_c = vat_of(net_c, rate_c)
          net_s = Money.money(net_c)

          [
            %{
              product_id: 0,
              code: "",
              description: "Протокол по #{article} от ЗДДС към фактура № #{inv.number}",
              quantity: "1",
              unit: "C62",
              unit_price: net_s,
              vat_rate: rate_str,
              net_amount: net_s,
              vat_amount: Money.money(vat_c),
              total_amount: Money.money(net_c + vat_c)
            }
          ]
        else
          Enum.map(src_lines, fn line ->
            net_c = Money.cents(line.net_amount) || 0
            line_rate = Money.cents(line.vat_rate) || 0
            r_c = if line_rate > 0, do: line_rate, else: rate_c
            vat_c = vat_of(net_c, r_c)

            %{
              product_id: line.product_id,
              code: line.code,
              description: line.description,
              quantity: line.quantity,
              unit: line.unit,
              unit_price: line.unit_price,
              vat_rate: Money.money(r_c),
              net_amount: Money.money(net_c),
              vat_amount: Money.money(vat_c),
              total_amount: Money.money(net_c + vat_c)
            }
          end)
        end

      head = %{
        direction: "in",
        document_type: "09",
        number: number,
        issue_date: issue_date,
        due_date: "",
        tax_event_date: issue_date,
        accounting_month: Head.month_of(issue_date, inv.accounting_month),
        counterpart_id: inv.counterpart_id,
        currency: inv.currency,
        currency_rate: inv.currency_rate,
        payment_method: "",
        notes:
          "Протокол по #{article} от ЗДДС към входяща фактура № #{inv.number} от #{inv.issue_date}",
        discount_percent: "0",
        discount_amount: "0",
        vat_exemption_reason: "",
        original_invoice_id: inv.id,
        location_id: inv.location_id,
        bank_account_id: 0,
        exclude_vat: 0,
        vat_article: article,
        customs_statistical: "",
        customs_duty: "",
        customs_vat: ""
      }

      finish(
        company_id,
        sub,
        inv,
        head,
        new_lines,
        "Създаден Протокол по #{article} № #{number} към фактура № #{inv.number}"
      )
    end
  end

  def issue_customs(company_id, sub, id, params) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         :ok <- incoming(inv, "митническа декларация се издава само към входяща фактура") do
      number = String.trim(string(params, "number"))

      if number == "" do
        {:error, {422, "номерът на митническата декларация (MRN) е задължителен"}}
      else
        issue_date = default(params, "issue_date", inv.issue_date)
        stat_raw = default(params, "customs_statistical", inv.net_amount)
        duty_raw = default(params, "customs_duty", "0")

        with {:ok, stat_c} <- cents_or(stat_raw, "невалидна статистическа стойност"),
             {:ok, duty_c} <- cents_or(duty_raw, "невалидно мито"),
             {:ok, vat_c} <- customs_vat(params, stat_c + duty_c) do
          base_c = stat_c + duty_c
          base_s = Money.money(base_c)
          vat_s = Money.money(vat_c)
          src_lines = Invoicing.lines_of(inv.id)

          first_prod =
            case src_lines do
              [first | _] -> first.product_id
              [] -> 0
            end

          line = %{
            product_id: first_prod,
            code: "",
            description:
              "Митническа декларация № #{number} към фактура № #{inv.number} (Стат. ст-ст #{Money.money(stat_c)}, Мито #{Money.money(duty_c)})",
            quantity: "1",
            unit: "C62",
            unit_price: base_s,
            vat_rate: "20.00",
            net_amount: base_s,
            vat_amount: vat_s,
            total_amount: Money.money(base_c + vat_c)
          }

          head = %{
            direction: "in",
            document_type: "07",
            number: number,
            issue_date: issue_date,
            due_date: "",
            tax_event_date: issue_date,
            accounting_month: Head.month_of(issue_date, inv.accounting_month),
            counterpart_id: 0,
            currency: "EUR",
            currency_rate: "1",
            payment_method: "",
            notes:
              "Митническа декларация № #{number} към фактура № #{inv.number} (#{inv.counterpart_name}) — Разчети с митници",
            discount_percent: "0",
            discount_amount: "0",
            vat_exemption_reason: "",
            original_invoice_id: inv.id,
            location_id: inv.location_id,
            bank_account_id: 0,
            exclude_vat: 0,
            vat_article: "",
            customs_statistical: Money.money(stat_c),
            customs_duty: Money.money(duty_c),
            customs_vat: vat_s
          }

          finish(
            company_id,
            sub,
            inv,
            head,
            [line],
            "Създадена Митническа декларация № #{number} към фактура № #{inv.number}"
          )
        end
      end
    end
  end

  ## Вътрешни

  defp finish(company_id, sub, _inv, head, lines, summary_prefix) do
    with {:ok, name} <- Lines.prepare(company_id, head, 0),
         {:ok, new_inv} <- Invoicing.insert_header(company_id, head, name, lines),
         {:ok, after_value} <- Read.detail(company_id, sub, new_inv.id) do
      total = Map.get(after_value, :total_amount, "0.00")
      curr = Map.get(after_value, :currency, "EUR")

      Audit.record(
        company_id,
        sub,
        "invoice",
        new_inv.id,
        head.number,
        "create",
        "#{summary_prefix}, сума #{total} #{curr}",
        "",
        "#{total} #{curr}",
        nil,
        after_value
      )

      Read.detail(company_id, sub, new_inv.id)
    end
  end

  defp incoming(%{direction: "in"}, _message), do: :ok
  defp incoming(_, message), do: {:error, {422, message}}

  defp vat_of(net_cents, rate_cents) do
    prod = net_cents * rate_cents
    if prod >= 0, do: Kernel.div(prod + 5000, 10_000), else: Kernel.div(prod - 5000, 10_000)
  end

  defp customs_vat(params, base_c) do
    raw = string(params, "customs_vat")

    if String.trim(raw) == "" do
      {:ok, vat_of(base_c, 2000)}
    else
      cents_or(raw, "невалидно митническо ДДС")
    end
  end

  defp cents_or(raw, message) do
    case Money.cents(raw) do
      nil -> {:error, {422, message}}
      cents -> {:ok, cents}
    end
  end

  defp default(params, key, fallback) do
    value = string(params, key)
    if String.trim(value) == "", do: fallback, else: String.trim(value)
  end

  defp string(params, key) do
    case Botyaga.Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end

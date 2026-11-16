defmodule Botyaga.Invoicing.Payment do
  @moduledoc """
  Автоматично плащане на осчетоводена фактура. Статията се прави от default
  сметките на фирмата: в брой → каса, карта → буферна сметка, банков превод →
  банка. Продажба: Дт плащане / Кт клиенти. Покупка: Дт доставчици / Кт плащане.
  """

  import Ecto.Query

  alias Botyaga.{Audit, Invoicing, Journal, Periods, Repo}
  alias Botyaga.Companies.{Company, Defaults}
  alias Botyaga.Invoicing.Money
  alias Botyaga.Journal.{Entry, Line}

  @payment_type "payment"

  def payment_type, do: @payment_type

  def pay(company_id, sub, id) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         :ok <- payable(inv),
         :ok <- not_paid(company_id, inv),
         company = Repo.get!(Company, company_id),
         {:ok, method} <- method_of(inv.payment_method),
         {:ok, pay_acct} <- payment_account(company, inv.direction, method),
         {:ok, cp_acct} <- Defaults.resolve(company, cp_role(inv.direction)),
         :ok <- Periods.assert_open(company_id, inv.accounting_month) do
      amount = Money.amount_for_doc(inv.document_type, inv.total_amount)
      plan = plan_for(inv.direction, pay_acct, cp_acct, amount)
      {:ok, entry} = write_entry(inv, plan, method)

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        inv.number,
        "pay",
        "Плащане (#{method_label(method)}) на документ № #{inv.number} — #{inv.counterpart_name}, сума #{amount} #{inv.currency} (статия #{entry.id})",
        "#{amount} #{inv.currency}",
        "#{amount} #{inv.currency}",
        nil,
        nil
      )

      {:ok, %{id: entry.id, document_number: entry.document_number, amount: amount}}
    end
  end

  def unpay(company_id, sub, id) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         {:ok, entry} <- fetch_payment(company_id, inv.id) do
      Journal.wipe(entry.id)

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        inv.number,
        "unpay",
        "Отменено плащане на документ № #{inv.number} — #{inv.counterpart_name} (статия #{entry.id})",
        "",
        "",
        nil,
        nil
      )

      {:ok, nil}
    end
  end

  @doc "Статията за плащане на фактурата, ако има."
  def fetch_payment(company_id, invoice_id) do
    case Repo.one(
           from(e in Entry,
             where:
               e.company_id == ^company_id and e.document_id == ^invoice_id and
                 e.document_type == ^@payment_type,
             limit: 1
           )
         ) do
      nil -> {:error, {404, "фактурата няма плащане"}}
      entry -> {:ok, entry}
    end
  end

  defp payable(%{status: "posted"}), do: :ok
  defp payable(_), do: {:error, {422, "плаща се само осчетоводена фактура"}}

  defp not_paid(company_id, inv) do
    case fetch_payment(company_id, inv.id) do
      {:ok, _} -> {:error, {409, "фактурата вече е платена"}}
      {:error, _} -> :ok
    end
  end

  defp method_of(raw) do
    case raw |> String.trim() |> String.downcase() do
      "в брой" -> {:ok, :cash}
      "карта" -> {:ok, :card}
      "банков превод" -> {:ok, :bank}
      "" -> {:error, {422, "задайте начин на плащане на фактурата"}}
      other -> {:error, {422, "начинът на плащане „#{other}“ не се плаща автоматично"}}
    end
  end

  defp payment_account(company, _direction, :cash), do: Defaults.resolve(company, "cash")
  defp payment_account(company, _direction, :bank), do: Defaults.resolve(company, "bank")
  defp payment_account(company, "in", :card), do: Defaults.resolve(company, "card_purchase")
  defp payment_account(company, _direction, :card), do: Defaults.resolve(company, "card_sale")

  defp cp_role("in"), do: "suppliers"
  defp cp_role(_), do: "customers"

  defp plan_for("in", pay_acct, cp_acct, amount),
    do: [side(cp_acct, "debit", amount), side(pay_acct, "credit", amount)]

  defp plan_for(_direction, pay_acct, cp_acct, amount),
    do: [side(pay_acct, "debit", amount), side(cp_acct, "credit", amount)]

  defp side(account, direction, amount),
    do: %{account: account, direction: direction, amount: amount}

  defp method_label(:cash), do: "в брой"
  defp method_label(:card), do: "карта"
  defp method_label(:bank), do: "банков превод"

  defp write_entry(inv, plan, method) do
    desc = "Плащане (#{method_label(method)}) № #{inv.number} / #{inv.direction}"

    Repo.transaction(fn ->
      entry =
        Repo.insert!(%Entry{
          company_id: inv.company_id,
          entry_date: inv.issue_date,
          document_type: @payment_type,
          document_id: inv.id,
          document_number: "PAY-#{inv.number}",
          description: desc,
          vat_type: "",
          counterpart_id: inv.counterpart_id,
          counterpart_name: inv.counterpart_name,
          document_date: inv.issue_date,
          vat_period: inv.accounting_month
        })

      Enum.each(plan, fn jl ->
        Repo.insert!(%Line{
          entry_id: entry.id,
          account_id: jl.account.id,
          account_number: jl.account.number,
          account_name: jl.account.name,
          direction: jl.direction,
          amount: jl.amount,
          vat_amount: "0"
        })
      end)

      entry
    end)
  end
end

defmodule Botyaga.Invoicing.Post do
  @moduledoc """
  Осчетоводяване. Клиент/доставчик и ДДС сметките идват от default сметките на
  фирмата (`Companies.Defaults`); приход/разход/запаси — от артикула. Кредитното
  известие пази същите страни и слага минус. Целият пост е в една транзакция.
  """

  alias Botyaga.{Audit, Catalog, Invoicing, Journal, Periods, Repo}
  alias Botyaga.Companies.{Company, Defaults}
  alias Botyaga.Stock.Replay
  alias Botyaga.Invoicing.{Invoice, Money}
  alias Botyaga.Journal.{Entry, Line}

  def post(company_id, sub, id) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         :ok <- Periods.assert_open(company_id, inv.accounting_month),
         :ok <- postable(inv),
         {:ok, plan} <- plan_for(inv) do
      # Статията и складовият replay са в една транзакция: при грешка в replay
      # фактурата не остава „постната“ с полупроменени партиди.
      {:ok, body} =
        Repo.transaction(fn ->
          {:ok, body} = write_journal(inv, plan)
          Replay.rebuild(company_id, "9999-12-31")
          body
        end)

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        inv.number,
        "post",
        "Осчетоводен документ (#{Money.title(inv.document_type)}) № #{inv.number} — #{inv.counterpart_name}, сума #{inv.total_amount} #{inv.currency} (статия #{body.id})",
        "#{inv.total_amount} #{inv.currency}",
        "#{inv.total_amount} #{inv.currency}",
        nil,
        body
      )

      Audit.record(
        company_id,
        sub,
        "journal",
        body.id,
        inv.number,
        "create",
        "Осчетоводен документ (#{Money.title(inv.document_type)}) № #{inv.number} — #{inv.counterpart_name}",
        "",
        "#{inv.total_amount} #{inv.currency}",
        nil,
        body
      )

      {:ok, body}
    end
  end

  def unpost(company_id, sub, id) do
    with {:ok, inv} <- Invoicing.fetch(company_id, id),
         :ok <- unpostable(inv) do
      Repo.transaction(fn ->
        Enum.each(Invoicing.journal_ids(inv), &Journal.wipe/1)
        Repo.update!(Ecto.Changeset.change(inv, status: "draft", journal_entry_id: 0))
        Replay.rebuild(company_id, "9999-12-31")
      end)

      Audit.record(
        company_id,
        sub,
        "invoice",
        inv.id,
        inv.number,
        "unpost",
        "Върнат в чернова (отпостнат) документ (#{Money.title(inv.document_type)}) № #{inv.number} — #{inv.counterpart_name}, сума #{inv.total_amount} #{inv.currency}",
        "#{inv.total_amount} #{inv.currency}",
        "#{inv.total_amount} #{inv.currency}",
        nil,
        nil
      )

      {:ok, nil}
    end
  end

  def bulk_post(company_id, sub, ids), do: bulk(ids, &post(company_id, sub, &1), :posted)
  def bulk_unpost(company_id, sub, ids), do: bulk(ids, &unpost(company_id, sub, &1), :unposted)

  defp bulk(ids, fun, key) do
    {done, failed, results} =
      Enum.reduce(ids, {0, 0, []}, fn id, {done, failed, results} ->
        case fun.(id) do
          {:ok, _} ->
            {done + 1, failed, results ++ [%{id: id, ok: 1}]}

          {:error, {_status, detail}} ->
            {done, failed + 1, results ++ [%{id: id, ok: 0, error: detail}]}
        end
      end)

    %{key => done, failed: failed, results: results}
  end

  defp postable(%Invoice{status: "posted"}), do: {:error, {409, "фактурата е вече постната"}}

  defp postable(inv) do
    cond do
      Money.is_proforma(inv.document_type) ->
        {:error, {422, "проформата не е данъчен документ и не се осчетоводява"}}

      inv.direction not in ["in", "out"] ->
        {:error, {422, "direction must be 'in' or 'out'"}}

      true ->
        :ok
    end
  end

  defp unpostable(%Invoice{status: "posted"}), do: :ok
  defp unpostable(_), do: {:error, {422, "не е осчетоводена"}}

  defp plan_for(inv) do
    company = Repo.get!(Company, inv.company_id)

    with :ok <- oss_allowed(company, inv) do
      plan_for_company(company, inv)
    end
  end

  # OSS продажба се допуска само за фирма с включен OSS режим (регистриран е-магазин).
  defp oss_allowed(company, inv) do
    if inv.is_oss == 1 and company.oss_enabled != 1,
      do: {:error, {422, "фирмата няма включен OSS режим — активирайте го в настройките"}},
      else: :ok
  end

  defp plan_for_company(company, inv) do
    total = Money.amount_for_doc(inv.document_type, inv.total_amount)

    # Режим на маржа: фактурата е без ДДС; данъкът се начислява с месечния протокол.
    {vat, vat_cents} =
      if inv.is_margin == 1,
        do: {"0.00", 0},
        else:
          {Money.amount_for_doc(inv.document_type, inv.vat_amount),
           Money.cents(inv.vat_amount) || 0}

    lines = Invoicing.lines_of(inv.id)

    cond do
      # OSS деклариране (вид 81): влиза само в ДДС дневника, без счетоводна статия.
      inv.document_type == "81" ->
        {:ok, []}

      inv.direction == "in" and inv.document_type == "09" ->
        protocol_plan(company, vat, vat_cents)

      inv.direction == "in" and inv.document_type == "07" ->
        customs_plan(company, inv, vat_cents)

      inv.direction == "out" ->
        sales_plan(company, inv, lines, total, vat, vat_cents)

      true ->
        purchase_plan(company, inv, lines, total, vat, vat_cents)
    end
  end

  defp protocol_plan(_company, _vat, 0),
    do: {:error, {422, "протоколът по чл. 117 трябва да има начислен ДДС"}}

  defp protocol_plan(company, vat, _vat_cents) do
    with {:ok, a4531} <-
           acct_or_create(
             company,
             Defaults.number(company, "vat_purchase"),
             "Начислен данък върху добавената стойност за покупките"
           ),
         {:ok, a4532} <-
           acct_or_create(
             company,
             Defaults.number(company, "vat_sale"),
             "Начислен данък върху добавената стойност за продажбите"
           ) do
      {:ok, [side(a4531, "debit", vat, vat), side(a4532, "credit", vat, vat)]}
    end
  end

  defp customs_plan(company, inv, vat_cents) do
    duty_c = Money.cents(inv.customs_duty) || 0
    customs_vat = Money.cents(inv.customs_vat) || 0
    cvat_c = if customs_vat > 0, do: customs_vat, else: vat_cents

    if duty_c == 0 and cvat_c == 0 do
      {:error, {422, "митническата декларация трябва да съдържа мито или ДДС"}}
    else
      with {:ok, a458} <- acct_or_create(company, "458", "Разчети с митници"),
           {:ok, a4531} <-
             acct_or_create(
               company,
               Defaults.number(company, "vat_purchase"),
               "Начислен данък върху добавената стойност за покупките"
             ) do
        plan = []

        plan =
          if duty_c > 0 do
            case duty_expense_acct(company, inv) do
              {:ok, exp_acct} -> plan ++ [side(exp_acct, "debit", Money.money(duty_c), "0")]
              {:error, _} = error -> throw(error)
            end
          else
            plan
          end

        plan =
          if cvat_c > 0,
            do: plan ++ [side(a4531, "debit", Money.money(cvat_c), Money.money(cvat_c))],
            else: plan

        {:ok, plan ++ [side(a458, "credit", Money.money(duty_c + cvat_c), "0")]}
      end
    end
  catch
    {:error, _} = error -> error
  end

  defp sales_plan(company, inv, lines, total, vat, vat_cents) do
    {cp, vat_acc} = op_override(company, inv, lines)

    with {:ok, a411} <- pick_account(company, cp, "customers"),
         {:ok, a4532} <- vat_sale_account(company, inv, vat_acc) do
      plan = [side(a411, "debit", total, "0")]

      plan =
        Enum.reduce_while(lines, {:ok, plan}, fn line, {:ok, acc} ->
          net = Money.amount_for_doc(inv.document_type, line.net_amount)

          with {:ok, product} <- need_product(line.product_id, company),
               {:ok, acct} <- revenue_acct(company, product) do
            {:cont, {:ok, acc ++ [side(acct, "credit", net, "0")]}}
          else
            {:error, _} = error -> {:halt, error}
          end
        end)

      with {:ok, plan} <- plan do
        plan = if vat_cents != 0, do: plan ++ [side(a4532, "credit", vat, vat)], else: plan
        {:ok, plan}
      end
    end
  end

  defp purchase_plan(company, inv, lines, total, vat, vat_cents) do
    {cp, vat_acc} = op_override(company, inv, lines)

    with {:ok, a401} <- pick_account(company, cp, "suppliers"),
         {:ok, a4531} <- pick_account(company, vat_acc, "vat_purchase") do
      result =
        Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
          net = Money.amount_for_doc(inv.document_type, line.net_amount)

          with {:ok, product} <- need_product(line.product_id, company),
               :ok <- purchase_account(product),
               {:ok, acct} <- acct_id(product.inventory_account_id, company) do
            acc = acc ++ [side(acct, "debit", net, "0")]

            if product.auto_write_off == 1 do
              case expense_acct(company, product) do
                {:ok, expense} ->
                  {:cont,
                   {:ok,
                    acc ++ [side(expense, "debit", net, "0"), side(acct, "credit", net, "0")]}}

                {:error, _} = error ->
                  {:halt, error}
              end
            else
              {:cont, {:ok, acc}}
            end
          else
            {:error, _} = error -> {:halt, error}
          end
        end)

      with {:ok, plan} <- result do
        plan =
          if inv.exclude_vat == 0 and vat_cents != 0,
            do: plan ++ [side(a4531, "debit", vat, vat)],
            else: plan

        credit_amt =
          if inv.exclude_vat != 0,
            do: Money.amount_for_doc(inv.document_type, inv.net_amount),
            else: total

        {:ok, plan ++ [side(a401, "credit", credit_amt, "0")]}
      end
    end
  end

  # Междинната „ДДС операция“ може да зададе сметките; по подразбиране съвпадат
  # с ролите, така че стандартното осчетоводяване не се променя.
  defp op_override(company, inv, lines) do
    rate = dominant_rate(lines)

    case Botyaga.Vat.Operations.for_invoice(company.id, inv, rate) do
      nil -> {0, 0}
      op -> {op.counterpart_account_id, op.vat_account_id}
    end
  end

  defp dominant_rate(lines) do
    rates = Enum.map(lines, &to_string(&1.vat_rate))

    cond do
      "20" in rates -> "20"
      "9" in rates -> "9"
      true -> "0"
    end
  end

  defp pick_account(company, id, _role) when id > 0 do
    case Repo.get_by(Catalog.Account, id: id, company_id: company.id) do
      nil -> {:error, {422, "липсва сметка от ДДС операцията"}}
      a -> {:ok, a}
    end
  end

  defp pick_account(company, _id, role), do: Defaults.resolve(company, role)

  # OSS: чуждото ДДС отива в аналитична сметка по държава (453401 DE…), иначе 4534.
  defp vat_sale_account(company, inv, _vat_acc) when inv.is_oss == 1 do
    case Botyaga.Oss.Rates.resolve(company.id, inv.oss_country, inv.issue_date) do
      %{account_id: id} when id > 0 ->
        case Repo.get_by(Catalog.Account, id: id, company_id: company.id) do
          nil -> acct_or_create(company, Defaults.number(company, "oss_vat"), "ДДС по OSS режим")
          a -> {:ok, a}
        end

      _ ->
        acct_or_create(company, Defaults.number(company, "oss_vat"), "ДДС по OSS режим")
    end
  end

  defp vat_sale_account(company, _inv, vat_acc), do: pick_account(company, vat_acc, "vat_sale")

  defp side(account, direction, amount, vat_amount) do
    %{account: account, direction: direction, amount: amount, vat_amount: vat_amount}
  end

  defp need_product(product_id, _company) when product_id <= 0,
    do: {:error, {422, "ред без артикул"}}

  defp need_product(product_id, company) do
    case Repo.get_by(Catalog.Product, id: product_id, company_id: company.id) do
      nil -> {:error, {422, "ред без артикул"}}
      product -> {:ok, product}
    end
  end

  defp revenue_acct(company, %{revenue_account_id: id}) when id > 0,
    do: acct_id(id, company)

  defp revenue_acct(company, _product), do: Defaults.resolve(company, "revenues")

  defp expense_acct(company, %{expense_account_id: id}) when id > 0,
    do: acct_id(id, company)

  defp expense_acct(company, _product), do: Defaults.resolve(company, "expenses")

  defp purchase_account(%{inventory_account_id: id, name: name}) when id <= 0,
    do: {:error, {422, "артикулът #{name} няма сметка за покупка"}}

  defp purchase_account(_), do: :ok

  defp acct_number(company, number) do
    case Repo.get_by(Catalog.Account, number: number, company_id: company.id) do
      nil -> {:error, {422, "липсва сметка с номер #{number}"}}
      account -> {:ok, account}
    end
  end

  defp acct_id(id, company) do
    case Repo.get_by(Catalog.Account, id: id, company_id: company.id) do
      nil -> {:error, {422, "липсва сметка с id #{id}"}}
      account -> {:ok, account}
    end
  end

  defp acct_or_create(company, number, default_name) do
    case acct_number(company, number) do
      {:ok, account} ->
        {:ok, account}

      {:error, _} ->
        {:ok,
         Repo.insert!(%Catalog.Account{
           company_id: company.id,
           number: number,
           name: default_name,
           saft_account_type: number,
           analytic_type: "none"
         })}
    end
  end

  defp duty_expense_acct(company, inv) do
    candidates =
      if inv.original_invoice_id > 0 do
        case Invoicing.fetch(company, inv.original_invoice_id) do
          {:ok, orig} -> Invoicing.lines_of(orig.id)
          {:error, _} -> []
        end
      else
        []
      end ++ Invoicing.lines_of(inv.id)

    from_products =
      Enum.find_value(candidates, fn line ->
        case Repo.get_by(Catalog.Product, id: line.product_id, company_id: company.id) do
          %{inventory_account_id: id} when id > 0 ->
            case Repo.get_by(Catalog.Account, id: id, company_id: company.id) do
              nil -> nil
              account -> account
            end

          _ ->
            nil
        end
      end)

    case from_products do
      nil ->
        Enum.find_value(["304", "302", "609", "602"], fn number ->
          case acct_number(company, number) do
            {:ok, account} -> account
            _ -> nil
          end
        end) || acct_or_create(company, "609", "Други разходи")

      account ->
        {:ok, account}
    end
  end

  defp margin_purchase_in_journal?(inv) do
    case Repo.get_by(Catalog.Counterpart, id: inv.counterpart_id, company_id: inv.company_id) do
      nil -> false
      cp -> cp.is_individual != 1 and String.upcase(cp.country || "BG") == "BG"
    end
  end

  defp write_journal(inv, plan) do
    vat_type =
      cond do
        # Марж продажба: влиза само с информативни колони (без суми); протоколът начислява ДДС.
        inv.is_margin != 0 and inv.direction == "out" ->
          "sales"

        # Марж покупка: колона 9 само при BG фактура от фирма; от ФЛ/ЕС не влиза.
        inv.is_margin != 0 and inv.direction == "in" ->
          if margin_purchase_in_journal?(inv), do: "purchase", else: "no_vat"

        inv.exclude_vat != 0 ->
          "no_vat"

        inv.direction == "in" and inv.document_type == "09" ->
          "both"

        inv.direction == "out" ->
          "sales"

        true ->
          "purchase"
      end

    doc_label =
      if inv.document_type == "09" and String.trim(inv.vat_article || "") != "" do
        "Протокол по #{String.trim(inv.vat_article)} от ЗДДС"
      else
        Money.title(inv.document_type)
      end

    desc = "#{doc_label} #{inv.number} / #{inv.direction}"

    Repo.transaction(fn ->
      entry =
        Repo.insert!(%Entry{
          company_id: inv.company_id,
          entry_date: inv.issue_date,
          document_type: inv.document_type,
          document_id: inv.id,
          document_number: inv.number,
          description: desc,
          vat_type: vat_type,
          counterpart_id: inv.counterpart_id,
          counterpart_name: inv.counterpart_name,
          document_date: inv.issue_date,
          vat_period: inv.accounting_month
        })

      out_lines =
        Enum.map(plan, fn jl ->
          line =
            Repo.insert!(%Line{
              entry_id: entry.id,
              account_id: jl.account.id,
              account_number: jl.account.number,
              account_name: jl.account.name,
              direction: jl.direction,
              amount: jl.amount,
              vat_amount: jl.vat_amount
            })

          %{
            id: line.id,
            account_id: jl.account.id,
            account_number: jl.account.number,
            account_name: jl.account.name,
            direction: jl.direction,
            amount: jl.amount,
            vat_amount: jl.vat_amount
          }
        end)

      Repo.update!(Ecto.Changeset.change(inv, status: "posted", journal_entry_id: entry.id))

      %{
        id: entry.id,
        company_id: inv.company_id,
        entry_date: inv.issue_date,
        document_type: inv.document_type,
        document_id: inv.id,
        document_number: inv.number,
        description: desc,
        vat_type: vat_type,
        counterpart_id: inv.counterpart_id,
        counterpart_name: inv.counterpart_name,
        document_date: inv.issue_date,
        vat_period: inv.accounting_month,
        lines: out_lines
      }
    end)
  end
end

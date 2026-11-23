defmodule Botyaga.Companies do
  @moduledoc """
  Фирми, активна фирма, обекти, собственици, крайни майки, серии и табло.
  """

  import Ecto.Query

  alias Botyaga.Repo
  alias Botyaga.Accounts
  alias Botyaga.Access
  alias Botyaga.{Catalog, Stamp}
  alias Botyaga.Params
  alias Botyaga.Settings
  alias Botyaga.Companies.{Company, Location, Owner, Parent, Series}

  @string_fields ~w(name eik vat_number vat_period currency address city post_code phone email
                     website mol manager_eik accountant_name accountant_egn tax_authority nap_office
                     vat_submitter vat_purchase_goods vat_sales_goods inventory_valuation_method country manager_name manager_egn
                     authorized_person_name authorized_person_egn vat_branch_number tax_accounting_basis
                     tax_entity software_company_name software_id software_version is_part_of_group
                     street_name building_number address_building additional_address_detail address_type
                     region settings)

  def blank, do: %Company{}

  # Категории за „Вид на стоката/услугата“ в ДДС дневниците — падащото меню на
  # НАП. Стойността е ключ; в файла за НАП отива българската дума.
  @vat_goods %{
    "stock" => "Стока",
    "material" => "Материал",
    "product" => "Продукт",
    "service" => "Услуга",
    "asset" => "Актив",
    "advance" => "Аванс",
    "other" => "Друго"
  }

  def vat_goods_keys, do: Map.keys(@vat_goods)
  def vat_goods_label(key), do: Map.get(@vat_goods, key, "Стока")

  def get_company(id), do: Repo.get(Company, id)

  @doc "Списък с фирмите с достъп. Супер администраторът вижда всички."
  def index_for(%Accounts.User{is_super_admin: 1}) do
    Repo.all(from(c in Company, order_by: [asc: c.id]))
  end

  def index_for(%Accounts.User{id: user_id}) do
    ids = Access.company_ids_of(user_id)

    if ids == [] do
      []
    else
      Repo.all(from(c in Company, where: c.id in ^ids, order_by: [asc: c.id]))
    end
  end

  def create(params, actor) do
    with :ok <- require_super_admin(actor),
         {:ok, changeset} <- apply_params(blank(), params),
         :ok <- validate_required(changeset),
         :ok <- check_eik(Ecto.Changeset.get_field(changeset, :eik), nil) do
      company =
        changeset |> Ecto.Changeset.apply_changes() |> then(&%{&1 | created_at: Stamp.now()})

      company = Repo.insert!(company)
      {created, _skipped} = Catalog.seed_chart(company.id)
      {:ok, company, created}
    end
  end

  @doc "Нова фирма за публична регистрация — без запис, той е в транзакцията на регистрацията."
  def new_for_register(params) do
    with {:ok, changeset} <- apply_params(blank(), params),
         :ok <- check_eik(Ecto.Changeset.get_field(changeset, :eik), nil) do
      {:ok, changeset |> Ecto.Changeset.apply_changes() |> then(&%{&1 | created_at: Stamp.now()})}
    end
  end

  def update(id, params, actor) do
    with {:ok, company} <- fetch_accessible(actor, id),
         {:ok, changeset} <- apply_params(company, params),
         :ok <- check_eik(Ecto.Changeset.get_field(changeset, :eik), id) do
      {:ok, Repo.update!(changeset)}
    end
  end

  def delete(id, actor) do
    with :ok <- require_super_admin(actor),
         %Company{} <- Repo.get(Company, to_int(id)) do
      Repo.delete!(%Company{id: to_int(id)})
      {:ok, nil}
    else
      nil -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
    end
  end

  def fetch_accessible(actor, id) do
    id = to_int(id)

    if can_access?(actor, id) do
      case Repo.get(Company, id) do
        nil -> {:error, :not_found}
        company -> {:ok, company}
      end
    else
      {:error, :not_found}
    end
  end

  def can_access?(%Accounts.User{is_super_admin: 1}, _id), do: true

  def can_access?(%Accounts.User{id: user_id}, id) do
    id in Access.company_ids_of(user_id)
  end

  def active_key(sub), do: "активна_фирма:#{sub}"

  def active_company_id(sub) do
    Settings.get(active_key(sub)) |> to_int()
  end

  @doc """
  Активната фирма с проверка на членството. Без избрана се взема първата
  с достъп. Потребител без членство получава `{:error, :no_access}`.
  """
  def resolve_active(sub) do
    case Accounts.get_by_login(sub) do
      nil ->
        {:error, :not_found}

      user ->
        stored = active_company_id(sub)

        cond do
          user.is_super_admin == 1 ->
            {:ok, if(stored > 0, do: stored, else: 1)}

          stored > 0 and stored in Access.company_ids_of(user.id) ->
            {:ok, stored}

          Access.company_ids_of(user.id) != [] ->
            {:ok, Access.company_ids_of(user.id) |> hd()}

          true ->
            {:error, :no_access}
        end
    end
  end

  def active_company(sub) do
    case resolve_active(sub) do
      {:ok, id} -> Repo.get(Company, id)
      _ -> nil
    end
  end

  def set_active(sub, company_id) do
    actor = Accounts.get_by_login(sub)

    if access_allowed?(actor, company_id) do
      Settings.upsert(active_key(sub), to_string(company_id))
      {:ok, Repo.get(Company, company_id)}
    else
      {:error, :not_found}
    end
  end

  defp access_allowed?(%Accounts.User{is_super_admin: 1}, _), do: true

  defp access_allowed?(%Accounts.User{id: user_id}, company_id),
    do: company_id in Access.company_ids_of(user_id)

  def company_settings(company_id) do
    %{
      company: Repo.get(Company, company_id),
      locations:
        Repo.all(from(l in Location, where: l.company_id == ^company_id, order_by: [asc: l.id])),
      beneficial_owners:
        Repo.all(from(o in Owner, where: o.company_id == ^company_id, order_by: [asc: o.id])),
      ultimate_parents:
        Repo.all(from(p in Parent, where: p.company_id == ^company_id, order_by: [asc: p.id])),
      document_series:
        Repo.all(from(s in Series, where: s.company_id == ^company_id, order_by: [asc: s.id]))
    }
  end

  @doc "Табло: суми от фактурите на активната фирма."
  def dashboard(sub) do
    year = DateTime.utc_now() |> DateTime.to_date() |> then(& &1.year)
    company_id = active_company_id(sub)

    if company_id <= 0 do
      %{
        company_id: 0,
        year: year,
        invoices_draft: 0,
        invoices_posted: 0,
        receivables: "0.00",
        payables: "0.00",
        vat_output: "0.00",
        vat_input: "0.00",
        revenue_ytd: "0.00",
        expense_ytd: "0.00",
        bank_total: "0.00",
        recent: []
      }
    else
      invoices =
        Repo.all(
          from(i in Botyaga.Invoicing.Invoice,
            where: i.company_id == ^company_id,
            order_by: [desc: i.id]
          )
        )

      {draft, posted, receivables, payables, vat_out, vat_in, revenue, expense, recent} =
        Enum.reduce(invoices, {0, 0, d(), d(), d(), d(), d(), d(), []}, fn invoice, acc ->
          {draft, posted, recv, pay, vout, vin, rev, exp, recent} = acc
          net = decimal(invoice.net_amount)
          vat = decimal(invoice.vat_amount)
          total = decimal(invoice.total_amount)

          {draft, posted} =
            cond do
              invoice.status == "draft" -> {draft + 1, posted}
              invoice.status == "posted" -> {draft, posted + 1}
              true -> {draft, posted}
            end

          {recv, pay, vout, vin, rev, exp} =
            if invoice.direction == "out" do
              {Decimal.add(recv, total), pay, Decimal.add(vout, vat), vin, Decimal.add(rev, net),
               exp}
            else
              {recv, Decimal.add(pay, total), vout, Decimal.add(vin, vat), rev,
               Decimal.add(exp, net)}
            end

          recent =
            if length(recent) < 5 do
              recent ++
                [
                  %{
                    id: invoice.id,
                    number: invoice.number,
                    issue_date: invoice.issue_date,
                    counterpart_id: invoice.counterpart_id,
                    counterpart_name: invoice.counterpart_name,
                    currency: invoice.currency,
                    total_amount: invoice.total_amount,
                    status: invoice.status
                  }
                ]
            else
              recent
            end

          {draft, posted, recv, pay, vout, vin, rev, exp, recent}
        end)

      bank_total = d()

      %{
        company_id: company_id,
        year: year,
        invoices_draft: draft,
        invoices_posted: posted,
        receivables: money(receivables),
        payables: money(payables),
        vat_output: money(vat_out),
        vat_input: money(vat_in),
        revenue_ytd: money(revenue),
        expense_ytd: money(expense),
        bank_total: money(bank_total),
        recent: recent
      }
    end
  end

  ## Вътрешни помощници

  defp require_super_admin(%Accounts.User{is_super_admin: 1}), do: :ok
  defp require_super_admin(_), do: {:error, :forbidden}

  defp validate_required(changeset) do
    cond do
      blank?(Ecto.Changeset.get_field(changeset, :name)) ->
        {:error, {:unprocessable, "name е задължително"}}

      blank?(Ecto.Changeset.get_field(changeset, :eik)) ->
        {:error, {:unprocessable, "eik е задължителен"}}

      true ->
        :ok
    end
  end

  defp check_eik(eik, exclude_id) do
    eik = String.trim(eik || "")
    exclude_id = to_int(exclude_id)

    if eik == "" do
      :ok
    else
      query = from(c in Company, where: c.id != ^exclude_id, select: c.eik)

      taken =
        Repo.all(query)
        |> Enum.any?(fn existing ->
          String.trim(existing || "") |> String.downcase() == String.downcase(eik)
        end)

      if taken, do: {:error, {:conflict, "фирма с този ЕИК вече съществува"}}, else: :ok
    end
  end

  defp apply_params(company, params) when is_map(params) do
    string_changes =
      Enum.reduce_while(@string_fields, %{}, fn field, acc ->
        case Params.str(params, field) do
          :absent -> {:cont, acc}
          {:present, value} -> {:cont, Map.put(acc, String.to_existing_atom(field), value)}
          {:error, message} -> {:halt, {:error, {:unprocessable, message}}}
        end
      end)

    with changes when is_map(changes) <- string_changes,
         {:ok, is_vat_registered} <-
           optional_flag(params, "is_vat_registered", company.is_vat_registered),
         {:ok, fiscal_month} <-
           optional_int(params, "fiscal_year_start_month", company.fiscal_year_start_month),
         :ok <- check_branch(changes),
         :ok <- check_goods(changes) do
      changes =
        changes
        |> Map.put(:is_vat_registered, is_vat_registered)
        |> Map.put(:fiscal_year_start_month, fiscal_month)
        |> apply_defaults(company)

      {:ok, Ecto.Changeset.change(company, changes)}
    end
  end

  defp check_goods(changes) do
    Enum.reduce_while([:vat_purchase_goods, :vat_sales_goods], :ok, fn field, _ ->
      case Map.get(changes, field) do
        nil ->
          {:cont, :ok}

        raw ->
          if String.trim(raw) in vat_goods_keys() do
            {:cont, :ok}
          else
            {:halt, {:error, {422, "#{field} трябва да е една от категориите за ДДС дневника"}}}
          end
      end
    end)
  end

  # Клон/обособено звено в POKUPKI/PRODAGBI е цифрово поле (4), 0..9999.
  defp check_branch(changes) do
    case Map.get(changes, :vat_branch_number) do
      nil ->
        :ok

      raw ->
        t = String.trim(raw)

        if t == "" or String.match?(t, ~r/^[0-9]{1,4}$/) do
          :ok
        else
          {:error, {422, "vat_branch_number трябва да е число от 0 до 9999"}}
        end
    end
  end

  defp optional_flag(params, key, current) do
    case Params.flag(params, key) do
      nil -> {:ok, current}
      {:error, message} -> {:error, {:unprocessable, message}}
      value -> {:ok, value}
    end
  end

  defp optional_int(params, key, current) do
    case Params.integer(params, key) do
      nil -> {:ok, current}
      {:error, message} -> {:error, {:unprocessable, message}}
      value -> {:ok, value}
    end
  end

  defp apply_defaults(changes, company) do
    changes =
      if blank?(changes[:vat_period]),
        do: Map.put(changes, :vat_period, company.vat_period || "monthly"),
        else: changes

    changes =
      if blank?(changes[:currency]),
        do: Map.put(changes, :currency, company.currency || "EUR"),
        else: changes

    changes =
      if blank?(changes[:inventory_valuation_method]),
        do:
          Map.put(
            changes,
            :inventory_valuation_method,
            company.inventory_valuation_method || "WAC"
          ),
        else: changes

    changes =
      if blank?(Map.get(changes, :vat_submitter)),
        do: Map.put(changes, :vat_submitter, company.vat_submitter || "accountant"),
        else: changes

    changes =
      if blank?(Map.get(changes, :vat_purchase_goods)),
        do: Map.put(changes, :vat_purchase_goods, company.vat_purchase_goods || "stock"),
        else: changes

    changes =
      if blank?(Map.get(changes, :vat_sales_goods)),
        do: Map.put(changes, :vat_sales_goods, company.vat_sales_goods || "stock"),
        else: changes

    changes =
      if is_nil(Map.get(changes, :fiscal_year_start_month)) or
           changes[:fiscal_year_start_month] <= 0,
         do: Map.put(changes, :fiscal_year_start_month, 1),
         else: changes

    # Празен ДДС номер изчиства регистрацията по ДДС.
    if blank?(changes[:vat_number] || company.vat_number),
      do: Map.put(changes, :is_vat_registered, 0),
      else: changes
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp to_int(""), do: 0
  defp to_int(nil), do: 0

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_int(value) when is_integer(value), do: value

  defp d, do: Decimal.new(0)

  defp decimal(""), do: d()
  defp decimal(nil), do: d()

  defp decimal(value) when is_binary(value) do
    try do
      Decimal.new(value)
    rescue
      _ -> d()
    end
  end

  defp money(value) do
    value |> Decimal.round(2, :half_up) |> Decimal.to_string(:normal)
  end
end

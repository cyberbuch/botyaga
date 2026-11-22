defmodule Botyaga.Saft.Load do
  @moduledoc """
  Четене за SAF-T. Не пише в базата. Зарежда снимка (`Snap`) на фирмата: сметки,
  дневник, салда, контрагенти, стоки и документите (в `Load.Docs`). Порт на
  `saft_load.rs`. Редовете се филтрират по фирма още при зареждане.
  """

  import Ecto.Query

  alias Botyaga.Repo
  alias Botyaga.Saft.Xml
  alias Botyaga.Catalog.{Account, Counterpart, Product}
  alias Botyaga.Banking.Account, as: BankAccount
  alias Botyaga.Companies.{Company, Owner, Parent}
  alias Botyaga.Journal.{Entry, Line}
  alias Botyaga.Periods.OpeningBalance

  def load(company_id) do
    case Repo.get(Company, company_id) do
      nil ->
        {:error, {422, "няма фирма за експорт"}}

      c ->
        entries = entries_of(company_id)
        entry_ids = Enum.map(entries, & &1.id)

        snap = %{
          company_id: company_id,
          company: company(c),
          bank_accounts: bank_accounts_of(company_id),
          owners: owners_of(company_id),
          parents: parents_of(company_id),
          accounts: [],
          nra: %{},
          openings: openings_of(company_id),
          entries: entries,
          lines: lines_of(entry_ids),
          parties: parties_of(company_id),
          products: products_of(company_id)
        }

        {accounts, nra} = accounts_of(company_id)
        snap = %{snap | accounts: accounts, nra: nra}
        {:ok, Botyaga.Saft.Load.Docs.load(company_id, snap)}
    end
  end

  defp company(c) do
    %{
      name: c.name || "",
      eik: c.eik || "",
      vat: c.vat_number || "",
      currency: c.currency || "",
      city: c.city || "",
      post: c.post_code || "",
      phone: c.phone || "",
      email: c.email || "",
      website: c.website || "",
      mol: c.mol || "",
      fys: c.fiscal_year_start_month || 1,
      country: c.country || "",
      basis: c.tax_accounting_basis || "",
      entity: c.tax_entity || "",
      soft_name: c.software_company_name || "",
      soft_id: c.software_id || "",
      soft_ver: c.software_version || "",
      group: c.is_part_of_group || "",
      street: c.street_name || "",
      number: c.building_number || "",
      building: c.address_building || "",
      extra: c.additional_address_detail || "",
      addr_type: c.address_type || "",
      region: c.region || ""
    }
  end

  defp owners_of(company_id) do
    Repo.all(from(o in Owner, where: o.company_id == ^company_id, order_by: [asc: o.id]))
    |> Enum.map(
      &%{
        company_id: &1.company_id,
        first_bg: &1.first_name_bg || "",
        last_bg: &1.last_name_bg || "",
        egn: &1.egn || "",
        first_lat: &1.first_name_latin || "",
        last_lat: &1.last_name_latin || "",
        country: &1.country || ""
      }
    )
  end

  defp bank_accounts_of(company_id) do
    Repo.all(from(a in BankAccount, where: a.company_id == ^company_id, order_by: [asc: a.id]))
    |> Enum.map(
      &%{
        iban: String.trim(&1.iban || ""),
        account_number: String.trim(&1.account_number || "")
      }
    )
  end

  defp parents_of(company_id) do
    Repo.all(from(p in Parent, where: p.company_id == ^company_id, order_by: [asc: p.id]))
    |> Enum.map(
      &%{
        company_id: &1.company_id,
        name_bg: &1.name_bg || "",
        uic: &1.uic || "",
        name_lat: &1.name_latin || "",
        country: &1.country || ""
      }
    )
  end

  defp accounts_of(company_id) do
    Repo.all(from(a in Account, where: a.company_id == ^company_id, order_by: [asc: a.id]))
    |> Enum.reduce({[], %{}}, fn a, {accs, nra} ->
      case Xml.pack(a.saft_account_type, a.number) do
        nil ->
          {accs, nra}

        {code, firm} ->
          {accs ++ [%{id: a.id, name: a.name || "", nra: code, firm: firm}],
           Map.put(nra, a.id, code)}
      end
    end)
  end

  defp openings_of(company_id) do
    Repo.all(from(o in OpeningBalance, where: o.company_id == ^company_id, order_by: [asc: o.id]))
    |> Enum.map(
      &%{
        company_id: &1.company_id,
        year: &1.fiscal_year,
        account_id: &1.account_id,
        debit: Xml.money_of(&1.debit),
        credit: Xml.money_of(&1.credit),
        counterpart_id: &1.counterpart_id || 0,
        product_id: &1.product_id || 0,
        qty: &1.quantity || ""
      }
    )
  end

  defp entries_of(company_id) do
    Repo.all(from(e in Entry, where: e.company_id == ^company_id, order_by: [asc: e.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        date: &1.entry_date || "",
        description: &1.description || "",
        counterpart_id: &1.counterpart_id || 0
      }
    )
  end

  defp lines_of([]), do: %{}

  defp lines_of(entry_ids) do
    Repo.all(from(l in Line, where: l.entry_id in ^entry_ids, order_by: [asc: l.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        entry_id: &1.entry_id,
        account_id: &1.account_id,
        direction: &1.direction || "",
        amount: Xml.money_of(&1.amount),
        vat: Xml.money_of(&1.vat_amount)
      }
    )
    |> Enum.group_by(& &1.entry_id)
  end

  defp parties_of(company_id) do
    Repo.all(from(c in Counterpart, where: c.company_id == ^company_id, order_by: [asc: c.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        name: &1.name || "",
        kind: &1.counterpart_type || "",
        eik: &1.eik || "",
        vat: &1.vat_number || "",
        city: &1.city || "",
        post: &1.post_code || "",
        country: &1.country || "",
        street: &1.street_name || "",
        number: &1.building_number || "",
        building: &1.address_building || "",
        extra: &1.additional_address_detail || "",
        addr_type: &1.address_type || "",
        region: &1.region || ""
      }
    )
  end

  defp products_of(company_id) do
    Repo.all(from(p in Product, where: p.company_id == ^company_id, order_by: [asc: p.id]))
    |> Enum.map(
      &%{
        id: &1.id,
        company_id: &1.company_id,
        name: &1.name || "",
        code: &1.code || "",
        unit: &1.unit || "",
        cost: Xml.money_of(&1.cost_price),
        service: &1.is_service == 1,
        inventory: &1.is_inventory == 1,
        qty: &1.stock_quantity || "",
        value: Xml.money_of(&1.stock_value),
        inv_acc: &1.inventory_account_id || 0,
        product_type: &1.product_type || "",
        cn8_code: &1.cn8_code || ""
      }
    )
  end
end

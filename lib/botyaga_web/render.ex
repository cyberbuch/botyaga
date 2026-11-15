defmodule BotyagaWeb.Render do
  @moduledoc "Форматиране на отговорите: ключовете и редът са като в ytbuch."

  alias Botyaga.Stamp
  alias Botyaga.{Accounts.User, Access.Role, Access.Membership, Companies.Company}

  @default_limit 50
  @max_limit 500

  def company(%Company{} = company) do
    %{
      id: company.id,
      name: company.name,
      eik: company.eik,
      vat_number: company.vat_number,
      is_vat_registered: company.is_vat_registered,
      vat_period: company.vat_period,
      currency: company.currency,
      address: company.address,
      city: company.city,
      post_code: company.post_code,
      phone: company.phone,
      email: company.email,
      website: company.website,
      mol: company.mol,
      manager_eik: company.manager_eik,
      accountant_name: company.accountant_name,
      accountant_egn: company.accountant_egn,
      tax_authority: company.tax_authority,
      nap_office: company.nap_office,
      iban: company.iban,
      bic: company.bic,
      inventory_valuation_method: company.inventory_valuation_method,
      fiscal_year_start_month: company.fiscal_year_start_month,
      country: company.country,
      manager_name: company.manager_name,
      manager_egn: company.manager_egn,
      authorized_person_name: company.authorized_person_name,
      authorized_person_egn: company.authorized_person_egn,
      vat_branch_number: company.vat_branch_number,
      tax_accounting_basis: company.tax_accounting_basis,
      tax_entity: company.tax_entity,
      software_company_name: company.software_company_name,
      software_id: company.software_id,
      software_version: company.software_version,
      is_part_of_group: company.is_part_of_group,
      street_name: company.street_name,
      building_number: company.building_number,
      address_building: company.address_building,
      additional_address_detail: company.additional_address_detail,
      address_type: company.address_type,
      region: company.region,
      settings: company.settings,
      created_at: Stamp.to_stamp(company.created_at)
    }
  end

  def user(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      is_active: user.is_active,
      is_super_admin: user.is_super_admin,
      role_id: user.role_id,
      totp_enabled: user.totp_enabled,
      created_at: Stamp.to_stamp(user.created_at)
    }
  end

  def profile(user, permissions, memberships) do
    %{
      sub: user.username,
      id: user.id,
      email: user.email,
      username: user.username,
      name: user.name,
      is_super_admin: user.is_super_admin,
      role_id: user.role_id,
      totp_enabled: user.totp_enabled,
      permissions: permissions,
      companies: memberships
    }
  end

  def member(%Membership{} = membership, %User{} = user, role_name) do
    %{
      user_id: membership.user_id,
      email: user.email,
      name: user.name,
      is_active: user.is_active,
      role_id: membership.role_id,
      role: role_name,
      created_at: Stamp.to_stamp(membership.created_at)
    }
  end

  def membership(%{company_id: company_id, role_id: role_id, role: role, company_name: name}) do
    %{company_id: company_id, role_id: role_id, role: role, company_name: name}
  end

  def role(%Role{} = role) do
    %{
      id: role.id,
      name: role.name,
      description: role.description,
      permissions: Botyaga.Access.decode_perms(role.permissions),
      created_at: Stamp.to_stamp(role.created_at)
    }
  end

  def location(location) do
    %{
      id: location.id,
      name: location.name,
      location_type: location.location_type,
      street_name: location.street_name,
      building_number: location.building_number,
      city: location.city,
      post_code: location.post_code,
      region: location.region,
      country: location.country,
      is_main: location.is_main,
      company_id: location.company_id
    }
  end

  def owner(owner) do
    %{
      id: owner.id,
      first_name_bg: owner.first_name_bg,
      last_name_bg: owner.last_name_bg,
      egn: owner.egn,
      first_name_latin: owner.first_name_latin,
      last_name_latin: owner.last_name_latin,
      country: owner.country,
      ownership_percentage: owner.ownership_percentage
    }
  end

  def parent(parent) do
    %{
      id: parent.id,
      name_bg: parent.name_bg,
      uic: parent.uic,
      name_latin: parent.name_latin,
      country: parent.country
    }
  end

  def series(series) do
    %{
      id: series.id,
      name: series.name,
      document_types: series.document_types,
      pad_width: series.pad_width,
      start_number: series.start_number,
      next_number: series.next_number
    }
  end

  def account(account) do
    %{
      id: account.id,
      number: account.number,
      name: account.name,
      saft_account_type: account.saft_account_type,
      analytic_type: account.analytic_type,
      is_currency: account.is_currency == 1
    }
  end

  def counterpart(counterpart) do
    %{
      id: counterpart.id,
      name: counterpart.name,
      counterpart_type: counterpart.counterpart_type,
      eik: counterpart.eik,
      vat_number: counterpart.vat_number,
      address: counterpart.address,
      city: counterpart.city,
      post_code: counterpart.post_code,
      country: counterpart.country,
      contact_person: counterpart.contact_person,
      vies_address: counterpart.vies_address,
      street_name: counterpart.street_name,
      building_number: counterpart.building_number,
      address_building: counterpart.address_building,
      additional_address_detail: counterpart.additional_address_detail,
      address_type: counterpart.address_type,
      region: counterpart.region,
      email: counterpart.email,
      phone: counterpart.phone
    }
  end

  def product(product) do
    %{
      id: product.id,
      name: product.name,
      code: product.code,
      description: product.description,
      unit: product.unit,
      price: product.price,
      cost_price: product.cost_price,
      vat_rate: product.vat_rate,
      is_service: product.is_service,
      is_inventory: product.is_inventory,
      inventory_account_id: product.inventory_account_id,
      revenue_account_id: product.revenue_account_id,
      stock_quantity: product.stock_quantity,
      stock_value: product.stock_value,
      is_active: product.is_active,
      product_type: product.product_type,
      cn8_code: product.cn8_code,
      cn8_name: product.cn8_name,
      expense_account_id: product.expense_account_id,
      auto_write_off: product.auto_write_off
    }
  end

  @doc "Списък с `items`/`count`/`total`/`limit`/`offset`/`has_more`."
  def page(items, params) when is_list(items) do
    limit = int_param(params, "limit", @default_limit) |> clamp(1, @max_limit)
    offset = int_param(params, "offset", 0) |> clamp(0, 1_000_000)
    total = length(items)
    offset = min(offset, total)
    page = Enum.slice(items, offset, limit)
    count = length(page)

    %{
      items: page,
      count: count,
      total: total,
      limit: limit,
      offset: offset,
      has_more: offset + count < total
    }
  end

  def int_param(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      v when is_integer(v) ->
        v

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, ""} -> n
          _ -> default
        end

      _ ->
        default
    end
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)
end

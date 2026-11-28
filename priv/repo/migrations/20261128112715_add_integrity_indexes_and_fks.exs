defmodule Botyaga.Repo.Migrations.AddIntegrityIndexesAndFks do
  use Ecto.Migration

  @company_tables [
    :accounting_periods,
    :accounts,
    :attachments,
    :audit_logs,
    :bank_accounts,
    :bank_matching_rules,
    :bank_transactions,
    :beneficial_owners,
    :company_locations,
    :counterparts,
    :dividend_distributions,
    :dividends,
    :document_series,
    :fixed_asset_categories,
    :fixed_assets,
    :fs_line_formulas,
    :internal_docs,
    :invoices,
    :journal_entries,
    :kits,
    :margin_protocols,
    :material_issues,
    :opening_balances,
    :oss_declarations,
    :oss_reports,
    :oss_vat_rates,
    :product_name_mappings,
    :production_cards,
    :production_orders,
    :production_receipts,
    :products,
    :recipes,
    :saft_account_mappings,
    :stock_account_rules,
    :ultimate_parents,
    :user_companies,
    :vat_manual,
    :vat_operations
  ]

  # NB: user_id НЯМА FK — в login_events/audit_logs стойност 0 означава „няма
  # потребител“ (неуспешен вход) и е легитимна; изтриването на юзър се чисти
  # в кода (Accounts.delete_user).

  def up do
    # Липсващи индекси (всички останали таблици с company_id вече имат).
    create(index(:dividends, [:company_id]))
    create(index(:counterparts, [:company_id, :eik]))

    # Сираци преди FK: редове с company_id извън companies се трият — те и без
    # това са недостижими (всяка заявка е scoped по фирма). NULL остава (FK го
    # позволява) за таблиците с nullable company_id.
    Enum.each(@company_tables, fn t ->
      execute(
        "DELETE FROM #{t} WHERE company_id IS NOT NULL AND company_id NOT IN (SELECT id FROM companies)"
      )
    end)

    # Referential integrity: изтриване на фирма чисти и зависимите редове.
    Enum.each(@company_tables, fn t ->
      alter table(t) do
        modify(:company_id, references(:companies, type: :bigint, on_delete: :delete_all))
      end
    end)
  end

  def down do
    Enum.each(@company_tables, fn t ->
      drop(constraint(t, "#{t}_company_id_fkey"))
    end)

    drop(index(:counterparts, [:company_id, :eik]))
    drop(index(:dividends, [:company_id]))
  end
end

# Модел на данните

PostgreSQL през Ecto. Миграции в `priv/repo/migrations/` (10 файла, подредени
по фази). **Няма външни ключове** — връзките се пазят от приложението, за
да не се променя видимото поведение при триене. Идентификаторите са
`bigint`/identity.

Всички парични и количествени полета са **низове** (2 знака за пари, 4 за
количество). Времето е `utc_datetime`, а датите на документи — низове
(`YYYY-MM-DD`), защото така се записват в счетоводните документи.

## Таблици

### Потребители и достъп

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `users` | `email`, `username`, `password_hash`, `role`, `is_active`, `is_super_admin`, `role_id`, `totp_enabled`, `totp_secret_b32`, `totp_pending_b32`, `session_version`, `mfa_fails`, `mfa_lock_until` | уникални `email` и `username` |
| `roles` | `name`, `description`, `permissions` (JSON списък) | три роли по подразбиране |
| `user_companies` | `user_id`, `company_id`, `role_id` | членство; уникален двойка потребител+фирма |
| `user_recovery_codes` | `user_id`, `code_hash`, `used` | резервни кодове за 2FA |
| `password_reset_tokens` | `user_id`, `token_hash`, `expires_at`, `used` | забравена парола |

### Фирми

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `companies` | `name`, `eik`, `vat_number`, `is_vat_registered`, `vat_period`, `currency`, адресни полета, `mol`, `manager_*`, `accountant_*`, `tax_authority`, `nap_office`, `vat_submitter`, `inventory_valuation_method`, `fiscal_year_start_month`, `software_*`, `settings` (JSON) | `inventory_valuation_method` по подразбиране `WAC` |
| `company_locations` | `company_id`, `name`, `location_type`, адрес, `is_main` | обекти |
| `beneficial_owners` | `company_id`, имена (BG/латиница), `egn`, `ownership_percentage` | действителни собственици |
| `ultimate_parents` | `company_id`, `name_bg`, `uic`, `name_latin`, `country` | крайни майки |
| `document_series` | `company_id`, `name`, `document_types`, `pad_width`, `start_number`, `next_number` | номер на серия |

### Каталог

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `accounts` | `company_id`, `number`, `name`, `saft_account_type`, `analytic_type`, `is_currency` | уникан двойка фирма+номер |
| `counterparts` | `company_id`, `name`, `counterpart_type`, `eik`, `vat_number`, адрес, `vies_address`, `email`, `phone` | `counterpart_type` по подразбиране `both` |
| `products` | `company_id`, `name`, `code`, `unit`, `price`, `cost_price`, `vat_rate`, `is_service`, `is_inventory`, `inventory_account_id`, `revenue_account_id`, `expense_account_id`, `stock_quantity`, `stock_value`, `product_type`, `cn8_code`, `cn8_name`, `auto_write_off` | услугата нулира склада |

### Фактури и дневник

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `invoices` | `company_id`, `direction`, `document_type`, `number`, `issue_date`, `due_date`, `counterpart_id`, `counterpart_name`, `currency`, `net_amount`, `vat_amount`, `total_amount`, `status`, `payment_method`, `tax_event_date`, `accounting_month`, `currency_rate`, `discount_*`, `vat_exemption_reason`, `original_invoice_id`, `location_id`, `bank_account_id`, `journal_entry_id`, `exclude_vat`, `vat_article`, `customs_*` | чернова/осчетоводена/кредитно/проформа |
| `invoice_lines` | `invoice_id`, `code`, `description`, `quantity`, `unit`, `unit_price`, `vat_rate`, `net_amount`, `vat_amount`, `total_amount`, `product_id` | |
| `journal_entries` | `company_id`, `entry_date`, `document_type`, `document_id`, `document_number`, `description`, `vat_type`, `counterpart_id`, `counterpart_name`, `document_date`, `vat_period` | гланка на дневников запис |
| `journal_lines` | `entry_id`, `account_id`, `account_number`, `account_name`, `direction`, `amount`, `vat_amount`, `currency`, `fx_quantity`, `fx_rate` | `direction` е `debit`/`credit` |
| `accounting_periods` | `company_id`, `year`, `month`, `status`, `closed_at`, `notes` | уникан фирма+година+месец |
| `audit_logs` | `company_id`, `user_id`, `user_login`, `user_name`, `entity_type`, `entity_id`, `entity_number`, `action`, `summary`, `old_amount`, `new_amount`, `old_data`, `new_data` | одитна следа |

### Периоди и ДДС

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `opening_balances` | `company_id`, `fiscal_year`, `account_id`, `debit`, `credit`, `counterpart_id`, `product_id`, `quantity`, `description` | салдо не е оборот |
| `vat_manual` | `company_id`, `period`, `cell_33`, `cell_70`, `cell_71`, `cell_80`, `cell_81`, `cell_82` | ръчни клетки |

### Банки и активи

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `bank_accounts` | `company_id`, `iban`, `bic`, `bank_name`, `currency`, `account_number`, `gl_account_id`, `buffer_account_id`, `balance`, `statement_format` | ГЛ/буфер от сметкоплана; формат на извлечението |
| `bank_transactions` | `company_id`, `bank_account_id`, `txn_date`, `amount`, `currency`, `counterpart_name`, `counterpart_iban`, `description`, `reference`, `transaction_type`, `is_booked`, `is_allocated`, `journal_entry_id` | |
| `bank_matching_rules` | `company_id`, `name`, `keywords`, `direction`, `priority`, `is_active`, `account_id`, `counterpart_id` | |
| `fixed_asset_categories` | `company_id`, `name`, `cita_category`, `min/max_depreciation_rate`, `default_method`, `asset_account_id`, `depreciation_account_id`, `expense_account_id` | |
| `fixed_assets` | `company_id`, `name`, `inventory_number`, `category_id`, `acquisition_date`, `put_into_service_date`, `cost`, `salvage_value`, `useful_life_months`, `depreciation_method`, `accounting_depreciation_rate`, `tax_depreciation_rate`, `accumulated_depreciation`, `tax_accumulated_depreciation`, `status`, `is_conserved`, `location_id` | |
| `fixed_asset_events` | `asset_id`, `event_type`, `event_date`, `amount`, `prev_value`, `location`, `reason` | преоценка, местене, консервация, отписване |
| `exchange_rates` | `code`, `rate`, `date` | курсове на ЕЦБ за 1 EUR |

### Склад и производство

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `inventory_lots` | `product_id`, `invoice_id`, `invoice_line_id`, `received_date`, `quantity`, `quantity_remaining`, `unit_cost`, `location_id` | партиди за WAC/FIFO/LIFO |
| `stock_account_rules` | `company_id`, `kind`, `inventory_account_id`, `offset_account_id`, `clearing_account_id` | `goods`/`production`/`material` |
| `material_issues` | `company_id`, `number`, `doc_date`, `location_id`, `status`, `journal_entry_id` | МИ-{id} |
| `material_issue_lines` | `doc_id`, `product_id`, `quantity`, `unit_cost`, `amount`, `account_id`, `inventory_account_id`, `line_no` | |
| `internal_docs` | `company_id`, `number`, `doc_date`, `from_location_id`, `to_location_id`, `status`, `handed_by`, `received_by` | вътрешни протоколи |
| `internal_doc_lines` | `doc_id`, `line_kind`, `product_id`, `asset_id`, `quantity`, `unit_cost`, `amount`, `description` | стоки и ДМА |
| `recipes` | `company_id`, `code`, `name`, `output_product_id`, `output_quantity`, `output_unit`, `is_active` | |
| `recipe_lines` | `recipe_id`, `product_id`, `quantity`, `unit`, `wastage_percent`, `line_no` | |
| `production_orders` | `company_id`, `number`, `recipe_id`, `output_product_id`, `quantity`, `location_id`, `order_date`, `status`, `material_cost`, `journal_entry_id` | |
| `production_order_lines` | `order_id`, `product_id`, `product_name`, `quantity`, `unit`, `unit_cost`, `amount` | |
| `dividend_distributions` | `company_id`, `year`, `total_amount`, `decision_date`, `decision_number`, `status` | |
| `dividends` | `company_id`, `distribution_id`, `beneficial_owner_id`, `owner_name`, `owner_egn`, `ownership_percentage`, `gross_amount`, `tax_rate`, `tax_amount`, `net_amount`, `decision_date`, `payment_date`, `is_paid` | 5% данък |

### Отчети и SAF-T

| Таблица | Ключови полета | Бележка |
|---------|----------------|---------|
| `fs_line_formulas` | `company_id`, `statement`, `line_code`, `formula` | формули по СС 1/СС 7 |
| `saft_account_mappings` | `company_id`, `kind`, `type_code`, `debit_account`, `credit_account`, `debit_analytical`, `credit_analytical`, `description`, `is_active` | Дт/Кт → тип движение |
| `product_name_mappings` | `company_id`, `counterpart_id`, `scanned_name`, `product_id` | име от сканиран документ |

### Настройки

`settings` е списък от двойки ключ/стойност. Ключове:

| Ключ | Смисъл |
|------|--------|
| `app.name`, `app.url` | име и адрес на приложението (за писмата) |
| `default_accounts` | JSON карта роля → номер на сметка за автоматизация (виж [accounting.md](accounting.md)) |
| `auth.registration_enabled` | публична регистрация (`0`/`false` = изключена) |
| `auth.jwt_secret` | тайна за JWT — **не се връща през API** |
| `smtp.host`, `smtp.port`, `smtp.username`, `smtp.password`, `smtp.from_email`, `smtp.from_name`, `smtp.use_tls`, `smtp.enabled` | поща; `smtp.password` се маскира |
| `s3.endpoint`, `s3.bucket`, `s3.access_key`, `s3.secret_key`, `s3.region`, `s3.prefix` | архив; `s3.secret_key` се маскира |
| `активна_фирма:<user_id>` | активна фирма — не се връща |
| `totp_last:<user_id>` | последно ползван TOTP — не се връща |

`GET /v1/system-settings` връща сортиран списък с маскирани тайни; записът с
маска или празна стойност запазва старата тайна.

## Демо данни

`priv/repo/seeds.exs` е празен — демо данните се създават от тестовете и от
ръка през интерфейса. Сметкопланът се пълни с `POST /v1/accounts/seed-saft`
(идемпотентно) от каталога на НАП (`priv/catalog/saft_noms.json`).

## Каталози в кода

| Файл | Съдържание |
|------|------------|
| `priv/catalog/saft_noms.json` | номенклатури на НАП: стокови и активни движения, данъчни режими, плащания, типове фактури, данъци, кодове, продукти, мерни единици, региони, сметки |
| `priv/catalog/cn8.json` | КН8 (NC8_TARIC): глави, позиции и артикули за търсене по синоними |

## Интегритет

`GET /v1/system-settings/db-check` проверява: връзки, таблици, сираци по
фирма и документ, и баланс дебит = кредит.

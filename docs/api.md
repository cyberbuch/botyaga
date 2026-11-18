# API

JSON API на Phoenix, порт `8093`. Клиентът говори с него през интерфейса
(Next проксира `/v1` към API-то), но може и директно.

## Конвенции

- **Авторизация.** `Authorization: Bearer <token>`. Токен се взима от
  `POST /v1/auth/token` (и `POST /v1/auth/mfa`, когато е включена 2FA).
- **Грешки.** `{"detail": "текст"}` с HTTP статус по контракт: 400 за валидация,
  401 за липсващ/невалиден токен, 403 за липсващо право, 404 за непознат път
  или чужд ред, 409 за дубликат, 503 за недостъпна външна услуга.
- **Списъци.** Обвивка `items` / `count` / `total` / `limit` / `offset` /
  `has_more`. `limit` по подразбиране 50, максимум 500; `offset` максимум
  1 000 000.
- **Сумите са низове** — 2 знака за пари, 4 за количество.
- **Времето е UTC** във формат `%Y-%m-%dT%H:%M:%SZ`.
- **Фирма.** Данните са под активната фирма на потребителя; чужд ред дава 404.
- **Права.** Всеки път се сваля до permission ключ; суперадминистраторът минава
  навсякъде. Ключовете: `companies`, `users`, `roles`, `settings`, `accounts`,
  `counterparts`, `products`, `invoices`, `scans`, `journal`, `periods`, `vat`,
  `banking`, `assets`, `stock`, `production`, `dividends`, `reports`, `saft`,
  `rates`.
- **Лимит.** 300 заявки накуп / 20 в секунда на потребител; входните пътища —
  30 накуп / 2 в секунда на адрес, заключване след 10 неуспешни опита за 15
  минути.

## Здраве

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/health` | жив ли е процесът |
| GET | `/ready`, `/readyz` | готовност: `{"status":"ok","database":"up"}` |

## Вход и профил (публични пътища)

| Метод | Път | Описание |
|-------|-----|----------|
| POST | `/v1/auth/token` | вход с имейл/потребителско име и парола → токен |
| POST | `/v1/auth/mfa` | второ ниво (TOTP или резервен код) → токен |
| GET | `/v1/auth/registration-status` | регистрацията включена ли е |
| POST | `/v1/auth/register` | самостоятелна регистрация |
| POST | `/v1/auth/forgot-password` | писмо за смяна на парола |
| POST | `/v1/auth/reset-password` | смяна с токен от писмото |

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/me` | профил, права и членства |
| PATCH | `/v1/me` | име |
| POST | `/v1/me/password` | смяна на парола |
| POST | `/v1/me/email` | смяна на имейл |
| POST | `/v1/me/totp/start` | начал на 2FA (QR + ключ) |
| POST | `/v1/me/totp/confirm` | потвърждение на 2FA |
| POST | `/v1/me/totp/disable` | изключване на 2FA |

## Фирми и настройки

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/companies` | моите фирми |
| POST | `/v1/companies` | нова фирма (създателят става администратор) |
| GET | `/v1/companies/:id` | карта на фирмата |
| GET | `/v1/companies/:id/settings` | настройки на фирмата |
| PATCH | `/v1/companies/:id` | редакция |
| DELETE | `/v1/companies/:id` | изтриване |
| GET | `/v1/active-company` | активна фирма |
| PUT | `/v1/active-company` | смяна на активна фирма |
| GET | `/v1/dashboard` | табло |

Обекти, собственици, крайни майки, серии:

| Метод | Път |
|-------|-----|
| POST / PATCH / DELETE | `/v1/companies/:id/locations`, `/v1/company-locations/:id` |
| POST / PATCH / DELETE | `/v1/companies/:id/beneficial-owners`, `/v1/beneficial-owners/:id` |
| POST / PATCH / DELETE | `/v1/companies/:id/ultimate-parents`, `/v1/ultimate-parents/:id` |
| POST / PATCH / DELETE | `/v1/companies/:id/document-series`, `/v1/document-series/:id` |

Членства и права:

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/companies/:id/users` | членове на фирмата |
| PATCH / DELETE | `/v1/companies/:id/users/:user_id` | роля / премахване |
| GET / POST | `/v1/users` | потребители (суперадминистратор) |
| PATCH / DELETE | `/v1/users/:id` | редакция / изтриване |
| GET / POST | `/v1/roles` | роли |
| PATCH / DELETE | `/v1/roles/:id` | редакция / изтриване |

Системни настройки (суперадминистратор):

| Метод | Път | Описание |
|-------|-----|----------|
| GET / PUT | `/v1/system-settings` | ключ/стойност списък и запис |
| POST | `/v1/system-settings/smtp-test` | тест на пощата |
| GET | `/v1/system-settings/db-check` | интегритет на базата |
| POST | `/v1/system-settings/s3-test` | тест на S3 |
| POST | `/v1/system-settings/s3-backup` | бекъп сега |
| GET | `/v1/system-settings/s3-backups` | списък на архивите |
| POST | `/v1/system-settings/s3-delete` | изтриване на архив |

## Каталог

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/accounts` | сметкоплан |
| POST | `/v1/accounts/seed-saft` | seed от каталога на НАП (идемпотентен) |
| GET / PATCH / DELETE | `/v1/accounts/:id` | сметка |
| GET / POST | `/v1/counterparts` | контрагенти |
| GET | `/v1/counterparts/vies-lookup` | справка по VIES |
| POST | `/v1/counterparts/vies` | нов контрагент от VIES |
| GET / PATCH / DELETE | `/v1/counterparts/:id` | контрагент |
| GET / POST | `/v1/products` | стоки и услуги |
| POST | `/v1/products/cn8-suggest` | предложение по КН8 |
| GET / PATCH / DELETE | `/v1/products/:id` | артикул |
| GET | `/v1/saft/nomenclatures` | номенклатури на НАП |
| GET | `/v1/units` | мерни единици |

## Фактури и дневник

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/invoices` | списък / нова чернова |
| GET | `/v1/invoices/next-number` | следващ номер по серия |
| GET | `/v1/invoices/:id` | преглед |
| PATCH / DELETE | `/v1/invoices/:id` | редакция / изтриване |
| POST | `/v1/invoices/:id/post` | осчетоводяване |
| POST | `/v1/invoices/:id/pay` | автоматично плащане (в брой/карта от default; банка от избраната сметка) |
| POST | `/v1/invoices/:id/unpay` | отмяна на плащането |
| GET | `/v1/invoices/:id/print` | печат (PDF/DOCX/ODT) |
| GET | `/v1/invoices/:id/ubl` | UBL 2.1 експорт |
| POST | `/v1/invoices/:id/issue-protocol` | протокол по чл. 117 ЗДДС |
| POST | `/v1/invoices/:id/issue-customs` | митническа декларация |
| POST | `/v1/invoices/bulk/post`, `/bulk/unpost`, `/bulk/delete` | групови действия |

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/journal` | дневник (само ръчни записи) |
| GET | `/v1/journal/:id` | преглед |
| PUT / PATCH / DELETE | `/v1/journal/:id` | редакция / изтриване |
| POST | `/v1/journal/bulk/delete` | групово изтриване |

## Периоди и салда

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/accounting-periods` | 12 месеца |
| POST | `/v1/accounting-periods/close`, `/reopen` | затваряне / отваряне |
| GET / POST | `/v1/opening-balances` | начални салда |
| PATCH / DELETE | `/v1/opening-balances/:id` | редакция / изтриване |
| GET | `/v1/closing-operations/preview` | преглед на приключването |
| POST | `/v1/closing-operations/run` | изпълнение |

## ДДС

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/vat/registers` | дневници покупки/продажби |
| GET | `/v1/vat/return` | данъчен материал (клетки 01-01…01-82) |
| GET | `/v1/vat/export` | файлове за НАП (`DEKLAR.TXT`, `POKUPKI.TXT`, `PRODAGBI.TXT`, `VIES_YYYYMM.TXT`, `PPDDS_YYYYMM.zip`) |
| PUT | `/v1/vat/manual` | ръчни клетки |
| GET | `/v1/vat-exemptions` | основания за неначисляване (VATEX) |

## Банки и активи

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/bank-formats` | регистрирани формати на извлечения (key/name) |
| GET / POST | `/v1/bank-accounts` | банкови сметки |
| PATCH / DELETE | `/v1/bank-accounts/:id` | редакция / изтриване |
| GET | `/v1/bank-transactions` | транзакции |
| POST | `/v1/bank-transactions/preview` | преглед на импорт |
| POST | `/v1/bank-transactions/import` | импорт (CSV, MT940, XML) |
| POST | `/v1/bank-transactions/auto-allocate`, `/auto-allocate/preview` | автоматично разнасяне |
| POST | `/v1/bank-transactions/:id/book/preview` | преглед на записа преди осчетоводяване (без запис в базата) |
| POST | `/v1/bank-transactions/:id/book` | осчетоводяване **с потвърждение** (`confirm=true`) |
| POST | `/v1/bank-transactions/:id/reallocate` | разнасяне |
| DELETE | `/v1/bank-transactions/:id` | изтриване |
| POST | `/v1/bank-transactions/bulk/delete` | групово изтриване |
| GET / POST | `/v1/bank-matching-rules` | правила |
| POST | `/v1/bank-matching-rules/defaults` | примерни правила |
| PATCH / DELETE | `/v1/bank-matching-rules/:id` | редакция / изтриване |

ДМА:

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/fixed-asset-categories` | категории |
| PATCH / DELETE | `/v1/fixed-asset-categories/:id` | редакция / изтриване |
| GET / POST | `/v1/fixed-assets` | активи |
| GET / PATCH / DELETE | `/v1/fixed-assets/:id` | акт |
| POST | `/v1/fixed-assets/depreciation/preview`, `/post` | амортизация |
| POST | `/v1/fixed-assets/:id/revalue`, `/move`, `/conserve`, `/end-conserve`, `/dispose` | събития |
| GET | `/v1/fixed-assets/:id/events` | история |

## Склад и производство

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/stock/rules` | правила за изписване |
| DELETE | `/v1/stock/rules/:id` | изтриване |
| POST | `/v1/stock/rebuild` | преизчисление на наличността |
| POST | `/v1/stock/writeoff` | месечно изписване на себестойност |
| GET | `/v1/stock/report` | складова справка |
| GET | `/v1/inventory/at-location` | наличност по обект |

Материални изписвания и вътрешни протоколи:

| Метод | Път |
|-------|-----|
| GET / POST | `/v1/material-issues` |
| GET / PATCH / DELETE | `/v1/material-issues/:id` |
| POST | `/v1/material-issues/:id/confirm`, `/unpost` |
| GET | `/v1/internal-docs/next-number` |
| GET / POST | `/v1/internal-docs` |
| GET | `/v1/internal-docs/:id`, `/v1/internal-docs/:id/print` |
| PATCH / DELETE | `/v1/internal-docs/:id` |
| POST | `/v1/internal-docs/:id/confirm` |

Производство:

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/recipes` | рецепти |
| GET / PATCH / DELETE | `/v1/recipes/:id` | рецепта |
| GET / POST | `/v1/production-orders` | поръчки |
| GET / DELETE | `/v1/production-orders/:id` | поръчка |
| POST | `/v1/production-orders/:id/confirm` | потвърждение (със себестойност) |

Дивиденти:

| Метод | Път | Описание |
|-------|-----|----------|
| GET / POST | `/v1/dividend-distributions` | разпределения |
| GET / PATCH / DELETE | `/v1/dividend-distributions/:id` | разпределение |
| POST | `/v1/dividends/:id/pay` | плащане (5% данък) |

## Справки, отчети, SAF-T

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/reports?kind=…` | справка по `kind` |
| GET | `/v1/reports/export` | XLSX/ODS експорт на справка |
| GET | `/v1/fs/lines` | редове на финансовите отчети |
| GET / PUT | `/v1/fs/formulas` | формули |
| POST | `/v1/fs/formulas/defaults`, `/validate`, `/clear` | шаблони / проверка / изчистване |
| GET | `/v1/saft/export` | SAF-T XML (`period`, `mode=monthly\|annual\|ondemand`, `date_from`, `date_to`) |
| GET / POST | `/v1/saft/movement-mappings` | Дт/Кт → тип движение |
| POST | `/v1/saft/movement-mappings/defaults` | примерни съответствия |
| PATCH / DELETE | `/v1/saft/movement-mappings/:id` | редакция / изтриване |

`kind` на `/v1/reports`: `trial_balance`, `general_ledger`, `chronological`,
`counterpart_trial`, `counterpart_chrono`, `correspondence_ledger`,
`balance_sheet`, `income_statement`, `cash_flow`, `equity`, `stock`.

## Външни услуги и помощници

| Метод | Път | Описание |
|-------|-----|----------|
| POST | `/v1/scans/ubl` | UBL XML → чернова |
| POST | `/v1/scans/extract` | сканирана фактура → чернова (Mistral OCR) |
| GET / POST | `/v1/product-name-mappings` | име → артикул (съхранява се) |
| GET | `/v1/exchange-rates`, `/rate`, `/cross` | курсове на ЕЦБ |
| POST | `/v1/exchange-rates/import` | импорт на дневен/90-дневен фид |
| POST | `/v1/addresses/parse` | адрес → полета |

## Одит

| Метод | Път | Описание |
|-------|-----|----------|
| GET | `/v1/audit-logs` | одитна следа с филтри (`entity_type`, `entity_id`, `action`, `user`, `from`, `to`, `changed_only`, `q`) |
| GET | `/v1/audit-logs/:entity_type/:entity_id` | история на обект |

## Непознатен път

Всичко под `/v1`, което не е изброено, отваря `FallbackController` и връща
404 с `{"detail": …}`. Неизпълнението на път без право е 403, а не 404.

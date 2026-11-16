# Архитектура

## Слойове

```
Браузър ──HTTP──> Next.js (:3021) ──/v1 прокси──> Phoenix JSON API (:8093) ──> PostgreSQL
                     │                                  │
                     │                                  ├── RateLimit (ETS)
                     │                                  ├── Gate (JWT + права)
                     │                                  └── Bootstrap (старт)
                     │
                     └── печат: Chromium sidecar (Gotenberg, :8094)
```

- **API** — Phoenix 1.8, само JSON (без LiveView). Контролерите са тънки;
  цялата логика е в `lib/botyaga/`.
- **Интерфейс** — Next.js 16 / React 19 на порт 3021. Браузърът говори само с
  него; Next препраща `/v1`, `/health` и `/ready` към API-то.
- **База** — PostgreSQL през Ecto. Миграции в `priv/repo/migrations/`.
- **Печат** — отделен Chromium sidecar (Gotenberg + DejaVu). API-то изпраща
  HTML и получава PDF; без него PDF връща 503.

## Supervisor дърво

`Botyaga.Application` стартира в `one_for_one` стратегия:

| Дете | Роля |
|------|------|
| `BotyagaWeb.Telemetry` | метрики |
| `Botyaga.Repo` | Ecto репо |
| `Botyaga.RateLimit` | GenServer + ETS кошове за лимитите |
| `Botyaga.Bootstrap` | еднократни стъпки при старт (роли, JWT тайна, superadmin) |
| `DNSCluster` | резолв на имена (опция) |
| `Phoenix.PubSub` | pub/sub |
| `BotyagaWeb.Endpoint` | HTTP сървър |

`Botyaga.Bootstrap` при старт:

1. създава трите роли на фирма, ако липсват;
2. бекфилва членствата (потребител → фирма → роля);
3. взема/създава тайната за JWT (`BOTYAGA_JWT_SECRET` или `settings.auth.jwt_secret`);
4. при празна база създава `superadmin` — парола от `BOTYAGA_SUPERADMIN_PASSWORD`
   или еднократно генерирана (отпечатва се в лога).

## Заявка през API-то

1. `RateLimitGeneral` — общ лимит: 300 заявки накуп, 20/сек, ключ по
   потребител (верен токен) или по IP.
2. `Gate` — публични са само шестте `/v1/auth/*` входни пътя. Всичко друго
   иска `Authorization: Bearer`. Токенът се проверява сращу тайната, сметката
   трябва да съществува и да е активна, а `ver` (сесийна версия) — да съвпада.
   След това пътят се сваля до permission ключ; непознат път → 404, липсващо
   право → 403.
3. `RateLimitAuth` — по-строг лимит само на входните пътища: 30 накуп, 2/сек
   на адрес. След 10 неуспешни опита акаунтът се заключва за 15 минути.
4. Контролер → контекст → `Render`/`Respond` → JSON.

## Модули

Контекстите в `lib/botyaga/`:

| Контекст | Модули | Отговорност |
|----------|--------|-------------|
| `Accounts` | `accounts`, `jwt`, `totp`, `user`, `recovery_code`, `password_reset_token` | вход, пароли, 2FA, сесийна версия, забравена парола |
| `Access` | `access`, `role`, `membership` | роли, членства, права |
| `Companies` | `companies`, `company`, `location`, `owner`, `parent`, `related`, `series` | фирми, активна фирма, обекти, собственици, крайни майки, серии |
| `Catalog` | `catalog`, `accounts`, `account`, `counterparts`, `counterpart`, `products`, `product`, `cn8`, `cn8/synonyms` | сметкоплан, контрагенти, стоки, номенклатури, КН8 |
| `Invoicing` | `invoicing`, `head`, `lines`, `money`, `post`, `read`, `special`, `invoice`, `invoice_line` | фактури, редове, пост/отпост, протоколи |
| `Journal` | `journal`, `entry`, `line` | ръчни дневникови записи |
| `Periods` | `periods`, `period`, `opening_balance` | счетоводни месеци, начални салда |
| `Opening` | `opening` | начални салда (страни по НСС) |
| `Closing` | `closing` | приключвателни операции |
| `Vat` | `vat`, `line`, `files`, `fmt`, `ex`, `manual` | ДДС дневници, файлове за НАП, ръчни клетки, основания |
| `Banking` | `banking`, `account`, `transaction`, `tx`, `csv`, `xml`, `rule`, `rules` | банкови сметки, извлечения, правила, разнасяне |
| `Assets` | `assets`, `asset`, `category`, `event`, `ops` | ДМА, амортизация, събития |
| `Stock` | `stock`, `lot`, `rule`, `rules`, `replay`, `replay/load`, `journal`, `writeoff`, `material_issue(s)`, `internal_doc(s)` | наличност, партиди, правила, изписвания, протоколи |
| `Production` | `orders`, `order`, `order_line`, `recipes`, `recipe`, `recipe_line` | рецепти и поръчки за производство |
| `Dividends` | `dividends`, `distribution`, `dividend` | дивиденти и плащане |
| `Reports` | `reports`, `data`, `trial`, `book`, `corr`, `stock`, `fs`, `nom` | справки и финансови отчети |
| `FsFormulas` | `fs_formulas`, `formula` | формули на финансовите отчети |
| `Saft` | `saft`, `gl`, `src`, `mode`, `moves`, `annual`, `load`, `load/docs`, `ownership`, `mapping(s)`, `mappings_def`, `xml` | SAF-T XML по BG_SAFT_Schema V1.0.1 |
| `Printing` | `printing`, `load`, `invoice`, `idoc`, `pdf`, `office`, `office/odt`, `sheet`, `words` | PDF/DOCX/ODT/XLSX/ODS печат |
| `Ubl` | `ubl`, `parser`, `import` | UBL 2.1 / Peppol BIS 3.0 експорт и вход |
| `Pnmap` | `pnmap`, `mapping`, `absorb` | име от сканиран документ → артикул |
| `Rates` | `rates`, `rate` | курсове на ЕЦБ |
| `Vies` | `vies` | справка по VIES |
| `Addr` | `addr` | разбиване на адреси |
| `Scan` | `scan`, `mistral` | OCR на фактура чрез Mistral |
| `Audit` | `audit`, `log` | одитна следа |
| `Settings` | `settings`, `setting` | глобални настройки |
| Други | `dec`, `params`, `stamp`, `zip`, `db_check`, `backup`, `s3`, `s3/sign`, `emails`, `mailer`, `registration`, `bootstrap`, `rate_limit`, `release` | аритметика, формати, интеграция, бекъп, старт |

Уеб слоят в `lib/botyaga_web/`:

- `router.ex` — пътища и pipe-линии (`:api`, `:auth_limit`, `:gate`);
- `plugs/gate.ex` — авторизация; `plugs/rate_limit_*` — лимити;
  `plugs/client_key.ex` — ключ за коша (потребител или IP);
- `render.ex` — форматиране на обекти и списъци;
- `respond.ex` — `ok/2`, `no_content/1`, `attachment/4`, `error/2`;
- `controllers/*` — по един за всяка област;
- `endpoint.ex`, `telemetry.ex`, `error_json.ex`, `fallback_controller.ex`.

## Принципи

- **Една валута, една база.** EUR; суми като низове в JSON; вътрешно цяло
  число с мащаб 1 000 000 (`Dec`).
- **Изолация по `company_id`.** Чужд ред е 404, не грешка.
- **Deny by default.** Непознат път се отказва; липсващо право е 403.
- **Модулът е границата.** Дългите файлове се делят на модули с header-и,
  не се съкращават с коментари (мек gate 400 реда, твърд 600).
- **Тайните не са в кода.** JWT тайната е в базата или env; SMTP/S3 ключовете —
  в настройките, маскирани в API-то.

## Размер и тестове

- 245 теста в `test/botyaga` (домейн) и `test/botyaga_web` (контролери и
  маршрути), 0 грешки.
- `mix precommit` — компилация без предупреждения, неизползвани зависимости,
  формат и тестове.
- `./scripts/filesize.sh` — мек gate 400 реда, твърд 600.

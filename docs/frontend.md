# Интерфейс

Next.js 16 (16.3.2) + React 19 на порт **3021**, `output: "standalone"`.
Браузърът говори само с този порт — Next препраща `/v1`, `/health` и `/ready`
към API-то на `127.0.0.1:8093` (`BOTYAGA_API_PROXY`; в контейнерния стек —
`http://backend:8093`).

## Структура

```
frontend/
  app/            страници (App Router)
  components/     споделени компоненти
  lib/            api клиент, i18n, помощници
  middleware.ts   CSP и security headers
  next.config.ts  прокси и headers
```

## Страници

| Група | Страници |
|-------|----------|
| Вход | `login`, `register`, `forgot-password`, `reset-password` |
| Профил | `profile`, `security` |
| Фирми | `companies`, `settings` |
| Каталог | `accounts`, `counterparts`, `products`, `nomenclatures` |
| Фактури | `invoices`, `invoices/new`, `invoices/[id]`, `invoices/[id]/edit` |
| Дневник и периоди | `journal`, `opening-balances`, `accounting-periods` |
| ДДС | `vat` |
| Банки | `bank-accounts`, `bank-transactions` |
| Активи | `fixed-assets` |
| Склад | `stock`, `material-issues`, `internal-docs` (+ `new`, `[id]`, `[id]/edit`) |
| Производство | `production` |
| Дивиденти | `dividends` |
| Справки | `reports`, `saft`, `saft-movement-mappings`, `audit` |
| Външни услуги | `exchange-rates`, `scan` |
| Админ | `admin`, `users`, `roles` |
| Табло | `page` (начало) |

## Настройки на фирмата

Страница `settings` с табове: Фирма, SAF-T/Собственици, Номерация, Финансови
отчети, Склад, Приключване, **Автоматизация** (default сметки за пост и
плащания), Потребители. Таб „Автоматизация“ записва `settings.default_accounts`.

## Навигация и права

Страничната лента (`AppShell`) се събира от списък от елементи с `href`, етикет
(`nav.*` в речника) и permission ключ. Елемент с `superOnly` се вижда само за
суперадминистратор. Ключовете съвпадат с тези в API-то (`companies`, `accounts`,
`invoices`, `banking`, `stock`, `reports`, `saft`, `users` и т.н.).

## Авторизация

Токенът се пази в `localStorage` под ключа `botyaga.token`
(`lib/storage.ts`, `useSyncExternalStore` — хидратационно-безопасно).
`AuthProvider` държи сесията, `RequireAuth` пази страниците. `lib/api.ts` слага
заглавния ред и форматира грешките (`detail`, включително списъци от
`{loc, msg}`).

## Безопасност

`middleware.ts` слага `Content-Security-Policy` с  nonce на всяка заявка,
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
`Referrer-Policy`, `Permissions-Policy` и `Strict-Transport-Security`.
`next.config.ts` дублира header-ите за статични файлове.

## Преводи

Речници в `lib/i18n-*.ts`: български (по подразбиране) и английски. Ключовете са
общи за двата езика; при липса се връща българският.

## Тестване и разработка

```bash
npm install
npm run dev        # http://127.0.0.1:3021
npm run test       # vitest
npm run lint       # eslint
```

Тестовете са на компоненти и помощници (`components/*.test.tsx`,
`lib/html.test.ts`).

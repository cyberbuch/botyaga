# botyaga — счетоводна програма

**botyaga** е самостоятелна счетоводна програма: JSON API на
**Elixir + Phoenix + Ecto + PostgreSQL** и интерфейс на **Next.js 16**.
Покрива целия счетоводен цикъл — фирми и обекти, сметкоплан, фактури,
дневник, счетоводни периоди, ДДС, банки, дълготрайни активи, склад,
производство, дивиденти, справки, финансови отчети с формули, SAF-T XML,
печат (PDF/DOCX/ODT/XLSX/ODS), UBL 2.1 експорт и вход, курсове на ЕЦБ,
VIES, адреси и OCR, одитна следа, интегритет на базата и S3 бекъп.

> **Статус: продуктът е завършен. 245 теста зелени** (проверено на 2026-11-16).
> Работят вход, профил, 2FA, фирми, обекти, собственици, майки, серии,
> членства, табло, настройки, gate, сметкоплан, контрагенти, стоки,
> номенклатури, КН8, фактури, осчетоводяване в транзакция, ръчен дневник,
> периоди, начални салда, приключване, одит, ДДС, банки, ДМА, склад
> (WAC/FIFO/LIFO), производство, вътрешни протоколи, дивиденти, справки,
> финансови отчети, SAF-T XML (месечен/годишен/при поискване), печат, UBL,
> ЕЦБ курсове, VIES, адреси и OCR (Mistral), db-check и S3 бекъп.

## Документация

Подробната документация е в [`docs/`](docs/):

- [architecture.md](docs/architecture.md) — стек, слоеве, модули, принципи
- [api.md](docs/api.md) — конвенции и пълен списък на API пътищата
- [data.md](docs/data.md) — таблици, ключове, настройки
- [accounting.md](docs/accounting.md) — фирми, сметкоплан, фактури, дневник, периоди
- [vat-banking.md](docs/vat-banking.md) — ДДС, банки, ДМА
- [stock-production.md](docs/stock-production.md) — склад, производство, дивиденти
- [reports-saft.md](docs/reports-saft.md) — справки, финансови отчети, SAF-T, одит
- [printing-ubl.md](docs/printing-ubl.md) — печат, UBL, курсове, VIES, OCR
- [frontend.md](docs/frontend.md) — интерфейс
- [deployment.md](docs/deployment.md) — стек, release, CI, бекъп, променливи

## Стек

| Слой | Технология |
|------|------------|
| Backend | Elixir + Phoenix (JSON API), Ecto |
| База | PostgreSQL |
| Frontend | Next.js 16 |
| Автентикация | JWT HS256, argon2id, TOTP 2FA |
| Печат | Chromium sidecar (Gotenberg) за PDF; DOCX/ODT/XLSX/ODS нативно |
| Деплой | release, билднат в CI → tarball на VPS, без toolchain на сървъра |

## Портове

| Услуга | Адрес |
|--------|-------|
| API (Phoenix) | `127.0.0.1:8093` |
| Интерфейс (Next.js) | `127.0.0.1:3021` |
| PostgreSQL | `127.0.0.1:5433` |
| Печат sidecar | `127.0.0.1:8094` |

## Стартиране локално

```bash
docker compose -f deploy/docker-compose.yml up -d --build   # пълен стек
```

Или само базата и backend:

```bash
docker compose -f deploy/docker-compose.yml up -d postgres   # PostgreSQL на 127.0.0.1:5433
mix setup                                                     # deps, база, миграции, seeds
mix phx.server                                                # API на http://127.0.0.1:8093
cd frontend && npm install && npm run dev                     # интерфейс на :3021
```

При първи старт с празна база се създава `superadmin` с еднократна парола в
лога. За парола по избор задай `BOTYAGA_SUPERADMIN_PASSWORD` преди първия
старт. Готовност: `GET /ready` → `{"status":"ok","database":"up"}`.

Проверка: `mix precommit` (формат, компилация без предупреждения, тестове) и
`./scripts/filesize.sh` (мек gate 400 реда, твърд 600).

## Променливи

| Променлива | По подразбиране |
|------------|-----------------|
| `BOTYAGA_JWT_SECRET` | няма — при първи старт се генерира и се пази в `settings` под `auth.jwt_secret` |
| `BOTYAGA_SUPERADMIN_PASSWORD` | няма — при празна база се генерира еднократна парола в лога |
| `BOTYAGA_DB_HOST` / `_PORT` / `_NAME` | `127.0.0.1` / `5433` / `botyaga_dev` |
| `PORT` | `8093` |

Пълният списък — в [deployment.md](docs/deployment.md).

## Принципи

- Базова валута **EUR**. Черно сторно: отрицателен знак, без обръщане на
  дебит и кредит. Сумите в JSON са низове (2 знака за пари, 4 за количество).
- `company_id` дели данните по фирма; чужд ред е 404.
- Всяка заявка минава през gate: без валиден токен няма достъп извън
  шестте публични входни пътя.
- Модулите се делят с header-и; gate 400 реда (мек) / 600 (твърд).
- Хранилището не съдържа лични данни и тайни. Демо данните са измислени.

## Лиценз

[BSD-3-Clause](LICENSE).

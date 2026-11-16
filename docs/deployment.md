# Разгръщане

## Контейнерен стек

```bash
docker compose -f deploy/docker-compose.yml up -d --build
```

| Сервис | Образ | Порт | Роля |
|--------|-------|------|------|
| `postgres` | `postgres:17` | 5433 → 5432 | база, том `botyaga_pgdata` |
| `print` | `deploy/print/Dockerfile` (Gotenberg 8 + DejaVu) | 8094 → 3000 | PDF печат |
| `backend` | `Dockerfile` (Elixir release) | 8093 | API |
| `frontend` | `frontend/Dockerfile` (Node 24, standalone) | 3021 | интерфейс |

`backend` зависи от здравия `postgres` и  healthcheck-ва на `/ready`;
`frontend` — от здравия `backend`. `entrypoint.sh` генерира `SECRET_KEY_BASE`
при липса, пуска миграциите (`Botyaga.Release.migrate()`) и после стартира
сървъра.

## Release образ

`Dockerfile` е multi-stage: `elixir:1.18-otp-27` компилира `mix release`, а
рантаймът е `debian:bookworm-slim` с OTP release-а и системните библиотеки за
NIF-овете. На VPS не е нужен toolchain.

Продукционна конфигурация ( `config/runtime.exs` ):

- `DATABASE_URL` — задължителен;
- `SECRET_KEY_BASE` — задължителен ( `mix phx.gen.secret` );
- `PHX_HOST`, `PORT` (по подразбиране 8093), `POOL_SIZE` (10), `ECTO_IPV6`.

## Променливи

| Променлива | По подразбиране | Смисъл |
|------------|-----------------|--------|
| `DATABASE_URL` | — (prod задължителна) | връзка с базата |
| `SECRET_KEY_BASE` | — (prod задължителна) | подписва cookies |
| `PHX_HOST` | `example.com` | външен хост |
| `PORT` | `8093` | порт на API-то |
| `POOL_SIZE` | `10` | размер на Ecto пул |
| `BOTYAGA_JWT_SECRET` | генерира се в базата | тайна за JWT |
| `BOTYAGA_SUPERADMIN_PASSWORD` | еднократна в лога | парола на `superadmin` при празна база |
| `BOTYAGA_PRINT_URL` | празно | адрес на PDF sidecar; без него PDF е 503 |
| `BOTYAGA_DB_USER` / `_PASSWORD` / `_HOST` / `_PORT` / `_NAME` | `postgres`/`postgres`/`127.0.0.1`/`5433`/`botyaga_dev` | база за dev/test |
| `BOTYAGA_API_PROXY` | `http://127.0.0.1:8093` | build arg на интерфейса: накъде препраща `/v1` |
| `NEXT_PUBLIC_API_URL` | празно | директен адрес на API-то от браузъра |

## CI

`.gitlab-ci.yml`, образ `elixir:1.18-otp-27`, база `postgres:17`:

- **test** — `./scripts/filesize.sh` (мек 400 / твърд 600 реда) и
  `mix precommit` (компилация без предупреждения, неизползвани зависимости,
  формат, тестове);
- **release** — при tag: `mix release` и артефакт `botyaga-*.tar.gz` (живее 1
  седмица).

## Бекъп

`Backup` прави `pg_dump` → gzip → S3 с име `botyaga_backup_*.sql.gz` в префикса
от настройките. Подписът е AWS Signature V4, path-style, без aws-sdk
(`S3.Sign` на `:crypto` + `Req`). Управление: `s3-test`, `s3-backup`,
`s3-backups`, `s3-delete` в системните настройки.

## Миграции

- локално: `mix setup` (deps, база, миграции, seeds);
- в контейнер: `entrypoint.sh` вика `Botyaga.Release.migrate()`;
- rollback: `bin/botyaga eval 'Botyaga.Release.rollback(Botyaga.Repo, <версия>)'`.

## Проверки

- `mix precommit` и `./scripts/filesize.sh`;
- `GET /ready` → `{"status":"ok","database":"up"}`;
- `GET /v1/system-settings/db-check` — интегритет на базата.

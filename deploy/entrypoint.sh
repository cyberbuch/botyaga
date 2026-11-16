#!/bin/sh
# Стартиране на release-а в контейнер: тайна при липса, миграции, после сървър.
set -e

# SECRET_KEY_BASE подписва cookies; за dev/test се генерира при липса.
# API-то ползва JWT от базата (settings), не тази тайна.
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
export DATABASE_URL="${DATABASE_URL:-ecto://postgres:postgres@postgres:5432/botyaga_dev}"
export PHX_SERVER=true
export BOTYAGA_PRINT_URL="${BOTYAGA_PRINT_URL:-http://print:3000}"

echo "Миграции..."
bin/botyaga eval "Botyaga.Release.migrate()"

echo "Старт на botyaga API :${PORT:-8093}"
exec bin/botyaga start
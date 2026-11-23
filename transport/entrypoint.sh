#!/bin/sh
# Стартиране на release-а в контейнер: миграции, после сървър.
set -e

export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
export DATABASE_URL="${DATABASE_URL:-ecto://postgres:postgres@postgres:5432/transport_dev}"
export BOTYAGA_DATABASE_URL="${BOTYAGA_DATABASE_URL:-ecto://postgres:postgres@postgres:5432/botyaga_dev}"
export PHX_SERVER=true

echo "Миграции..."
bin/transport eval "Transport.Release.migrate()"

echo "Старт на transport API :${PORT:-8096}"
exec bin/transport start

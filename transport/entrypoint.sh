#!/bin/sh
# Стартиране на release-а в контейнер: миграции, после сървър.
set -e

export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
# DATABASE_URL и BOTYAGA_DATABASE_URL са задължителни — без тях release-ът не стартира.
export PHX_SERVER=true

echo "Миграции..."
bin/transport eval "Transport.Release.migrate()"

echo "Старт на transport API :${PORT:-8096}"
exec bin/transport start

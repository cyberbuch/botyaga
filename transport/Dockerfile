# Multi-stage build на Elixir release (същият образ като botyaga: elixir:1.18-otp-27).
FROM elixir:1.18-otp-27 AS build

ENV MIX_ENV=prod
WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv
RUN mix compile && mix release

FROM debian:bookworm-slim AS app

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl libstdc++6 libgcc-s1 libncurses6 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/transport ./
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV HOME=/app \
    PORT=8096 \
    MIX_ENV=prod \
    LANG=C.UTF-8 \
    ELIXIR_ERL_OPTIONS="+fnu"

EXPOSE 8096

CMD ["/app/entrypoint.sh"]

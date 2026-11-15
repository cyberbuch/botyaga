# Chromium sidecar за PDF печат (Gotenberg) с вграден DejaVu за кирилица.
# Приложението праща HTML към /forms/chromium/convert/html и получава PDF.
FROM gotenberg/gotenberg:8

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
USER gotenberg

EXPOSE 3000
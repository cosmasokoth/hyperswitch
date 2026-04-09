# HyperSwitch router for Railway
# Uses the official standalone image and adds a migration entrypoint.
# All runtime config is overridden via ROUTER__* env vars set in Railway.

FROM juspaydotin/hyperswitch-router:standalone

USER root

# postgresql-client gives us pg_isready. The standalone image is Debian-based.
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash postgresql-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Migrations folder must be committed next to this Dockerfile.
# Copy it from https://github.com/juspay/hyperswitch/tree/main/migrations
COPY migrations /local/migrations

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]

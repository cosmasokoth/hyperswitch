FROM juspaydotin/hyperswitch-router:standalone

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash postgresql-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Overwrite the image's TOML with the upstream version (has all connector base_urls)
COPY config/docker_compose.toml /local/config/docker_compose.toml

COPY migrations /local/migrations
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
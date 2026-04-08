FROM juspaydotin/hyperswitch-router:standalone

USER root
RUN apk add --no-cache bash postgresql-client || \
    (apt-get update && apt-get install -y bash postgresql-client && rm -rf /var/lib/apt/lists/*)

COPY migrations /local/migrations
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

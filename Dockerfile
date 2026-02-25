FROM alpine:3.21

RUN apk add --no-cache bash curl bc docker-cli jq

COPY scripts/ /scripts/
COPY crontab /etc/crontabs/root

RUN chmod +x /scripts/*.sh

CMD ["crond", "-f", "-l", "2"]

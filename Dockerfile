FROM alpine:3.10
LABEL maintainer="anhgien <giencntt@gmail.com>"

RUN apk update && \
    apk add --no-cache wget curl
RUN apk update && \
    apk add --no-cache postgresql-client && \
    mkdir /backup
RUN curl https://dl.minio.io/client/mc/release/linux-amd64/mc > /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

ENV CRON_TIME="0 0 * * *" \
    PG_DB="--all-databases"

ADD restic_app /usr/local/bin/restic
RUN chmod +x /usr/local/bin/restic

ADD run.sh /run.sh
RUN chmod +x /run.sh
VOLUME ["/backup"]

ENTRYPOINT ["sh", "-c"]
CMD ["/run.sh"]

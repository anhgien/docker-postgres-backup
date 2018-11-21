FROM alpine
LABEL maintainer="anhgien <giencntt@gmail.com>"

RUN apk update && \
    apk add --no-cache wget curl
RUN apk update && \
    apk add --no-cache postgresql-client && \
    mkdir /backup

ENV CRON_TIME="0 0 * * *" \
    PG_DB="--all-databases"

ADD run.sh /run.sh
RUN chmod +x /run.sh
VOLUME ["/backup"]

ENTRYPOINT ["sh","-c"]
CMD ["/run.sh"]

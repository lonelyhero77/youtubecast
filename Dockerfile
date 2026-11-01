FROM golang:1.24-alpine AS supercronic-build

RUN go install github.com/aptible/supercronic@latest

FROM python:3.11-alpine

WORKDIR /app

RUN apk add --no-cache ffmpeg tini su-exec tzdata && \
    python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir yt-dlp

COPY --from=supercronic-build /go/bin/supercronic /usr/local/bin/supercronic

#CLONE REPOSITORY
ADD https://api.github.com/repos/lonelyhero77/youtubecast/git/refs/heads/main /version.json
RUN apk add --no-cache --virtual .build-deps git && \
    git clone https://github.com/lonelyhero77/youtubecast.git /app && \
    rm -rf /app/.git && \
    apk del .build-deps

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

#SET MOUNTPOINT
VOLUME ["/app/podcasts"]

ENTRYPOINT ["/sbin/tini", "-g", "--", "/usr/local/bin/docker-entrypoint"]

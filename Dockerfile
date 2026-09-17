FROM python:3.11-alpine

WORKDIR /app

#INSTALL DEPENDENCIES
RUN apk add --no-cache ffmpeg tini && \
    pip install --no-cache-dir yt-dlp

#CLONE REPOSITORY
ADD https://api.github.com/repos/lonelyhero77/youtubecast/git/refs/heads/main /version.json
RUN apk add --no-cache --virtual .build-deps git && \
    git clone https://github.com/lonelyhero77/youtubecast.git /app && \
    rm -rf /app/.git && \
    apk del .build-deps

#SET MOUNTPOINT
VOLUME ["/app/podcasts"]

#EXECUTE COMMANDS
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "cp /app/crontab /etc/crontabs/root && chmod 600 /etc/crontabs/root && python3 youtubecast.py & exec crond -f -l 2"]

#!/bin/sh
set -eu

PUID=${PUID:-1000}
PGID=${PGID:-1000}

case "$PUID" in
    ''|*[!0-9]*)
        echo "PUID must be a positive integer" >&2
        exit 64
        ;;
esac

case "$PGID" in
    ''|*[!0-9]*)
        echo "PGID must be a positive integer" >&2
        exit 64
        ;;
esac

if [ "$PUID" -eq 0 ] || [ "$PGID" -eq 0 ]; then
    echo "PUID and PGID must be non-zero" >&2
    exit 64
fi

chown -R "$PUID:$PGID" /opt/venv
chown "$PUID:$PGID" /app    
if [ -e /app/youtubecast.lock ]; then
    chown "$PUID:$PGID" /app/youtubecast.lock
fi

export PATH="/opt/venv/bin:$PATH"

exec su-exec "$PUID:$PGID" sh -c 'cd /app && python youtubecast.py & exec supercronic /app/crontab'
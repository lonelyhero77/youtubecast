# youtubecast

Turns YouTube channels/playlists into audio podcast feeds. Runs from cron,
downloads audio + thumbnails with yt-dlp, generates `channel.xml` (podcast RSS)
per source. Point a static webserver at the `root` folder and subscribe to
`<base_url>/<folder>/channel.xml`.

## Requirements

Python 3.11+:

```sh
sudo apt install python3-venv ffmpeg
python3 -m venv venv
venv/bin/pip install yt-dlp
```

Python < 3.11 additionally needs `tomli` (a backport of stdlib `tomllib`):

```sh
venv/bin/pip install tomli
```

## Configuration

Copy `config.example.toml` to `config.toml` next to the script and edit:

```toml
base_url = "https://podcasts.example.com/"
root     = "/home/youtubecast/podcasts"
backlog  = 1

[[podcasts]]
url    = "https://www.youtube.com/@SomeChannel"
title  = "Some Channel"
folder = "some-channel"

[[podcasts]]
url           = "https://www.youtube.com/playlist?list=PL0123456789abcdef0123456789abcdef"
title         = "Some Playlist"
folder        = "some-playlist"
backlog       = 3
backlog_order = "asc"
pubdate       = "download"
```

- `base_url` — public URL the webserver serves `root` at; include a trailing `/`
- `root` — folder where podcast folders are created (webserver docroot)
- `backlog` — how many latest videos to download when a source is added (default
  1); channel scans inspect up to the latest 100 videos
- `[[podcasts]]` — one per source: `url` (channel or playlist), `title` (podcast
  name), `folder` (folder name under `root`)

Optional, global or per-podcast (per-podcast wins):

- `backlog` — per-source override
- `thumbnail` — download and add video thumbnails to the feed (default `false`)
- `backlog_order` — how the source lists its videos, used to pick the newest
  `backlog` videos on first run: `"desc"` (default) means newest first, so they
  are taken from the beginning; `"asc"` means oldest first, taken from the end.
  Channels always list newest first; playlists depend on their sort order
- `lang` — episode metadata is fetched in the video's original language by
  default; set e.g. `lang = "ru"` to pin a language if YouTube ever starts
  serving auto-translated titles/descriptions
- `pubdate` — what becomes the episode's pubDate: `"upload"` (default) uses the
  video's original upload date; `"download"` uses the time the episode was
  downloaded, so old videos added to a playlist appear as new episodes

## File structure

```
youtubecast/
├── youtubecast.py
├── config.toml
├── venv/
├── youtubecast.lock    # prevents overlapping cron runs
├── cron.log
└── podcasts/           # `root` from config, serve this with a webserver
    ├── some-channel_logo.jpg   # put it here yourself, the feed references it
    ├── some-channel/
    │   ├── channel.xml     # podcast RSS feed
    │   ├── episodes.json   # episode metadata, channel.xml is rebuilt from it
    │   ├── seen.txt        # video IDs already handled
    │   ├── <video_id>.m4a  # episode audio
    │   └── <video_id>.jpg  # episode thumbnail
    ├── some-playlist_logo.jpg
    └── some-playlist/
        └── ...
```

New videos are detected as "not in `seen.txt`", i.e. new since last *download*,
not last check — a failed download retries on the next run. Delete an ID from
`seen.txt` (and its files) to re-download it. Channel root URLs are checked via
their Videos tab, and live or upcoming videos are skipped.

## Run manually

Run all configured podcasts, or pass an exact `title` from `config.toml` to
process only that podcast:

```sh
./venv/bin/python youtubecast.py
./venv/bin/python youtubecast.py "Some Channel"
```

## Cron

`crontab -e`:

```cron
# check sources hourly
0 * * * *  cd /path/to/youtubecast && ./venv/bin/python youtubecast.py >> cron.log 2>&1
# update yt-dlp weekly (Mon 05:15) — yt-dlp is a pip package inside the
# project venv, so pip upgrades it in place
15 5 * * 1 /path/to/youtubecast/venv/bin/pip install -q --upgrade yt-dlp >> /path/to/youtubecast/cron.log 2>&1
```

## Docker

The Compose service defaults to UID:GID `1000:1000`. Set `PUID` and `PGID` in
the Compose `.env` file to match the user that should own downloaded files.
Make sure the host `./podcasts` directory is writable by that UID:GID; the
container does not change ownership of the bind-mounted directory. Set
`root = "/app/podcasts"` in `config.toml` so generated files go into that mount.
The container starts one check immediately and also follows the configured
schedules.

The container reads schedules from the repository's `crontab` file, mounted
read-only at `/app/crontab`. Add one five-field cron line per task; commands run
as `PUID:PGID`:

```cron
0 21 * * * cd /app && /opt/venv/bin/python /app/youtubecast.py
15 5 * * 1 /opt/venv/bin/pip install -q --upgrade yt-dlp
```

Edit `crontab` to add or change tasks, then restart the container to
load the updated schedule. A `yt-dlp` upgrade made inside the running container
is reset when it is recreated from an older image. Supercronic is fetched at
its latest version when the image is built; rebuild and redeploy the image to
apply newer releases.

### Nginx token allowlist

Copy `nginx/tokens.map.example` to `nginx/tokens.map`, replace the example
value, and add one quoted token mapping per line. `nginx/tokens.map` is ignored
by Git:

```nginx
"64-character-hex-token-one" 1;
"64-character-hex-token-two" 1;
```

The application-specific server config is in `nginx/conf.d/default.conf` and
is mounted over the image's default server config. Its token map includes
`/etc/nginx/tokens.map` in the `http` context:

```nginx
map $arg_token $is_valid_token {
  default 0;
  include /etc/nginx/tokens.map;
}
```

In the protected `location`, substitute each feed's token marker with the
requesting token:

```nginx
sub_filter_types application/rss+xml application/xml text/xml;
sub_filter_once off;
sub_filter '__REQUEST_TOKEN__' $arg_token;
```

Directory listing is disabled, so use the `channel.xml` URL or its direct media
links rather than browsing folders. Requests for `episodes.json` and `seen.txt`
return 404 even with a valid token.

The `nginx` service in `docker-compose.yml` mounts this server config, the token
map, and the podcast directory. Create `nginx/tokens.map` before starting it.
The `ngx_http_sub_module` must be enabled in Nginx. Each feed response then
contains only the token used to request that feed, and its audio and image URLs
use the same token. All listed tokens still grant access to every podcast; to
revoke one, remove its entry and reload Nginx. Old `channel.xml` files are
regenerated with token markers on the next podcast check.

The checked-in server config uses `server_name _` and does not trust forwarded
client IP headers. Its access log records `$uri` without query arguments and
omits the Referer, so the token is not written to this Nginx access log. Apply
the same logging rule at any reverse proxy in front of it. If deploying behind
a reverse proxy and needing the real client IP, configure `set_real_ip_from`
only for that proxy's trusted IP ranges.

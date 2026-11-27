#!/bin/bash
# Uploads a wallpaper video and its thumbnail to Cloudflare Workers KV (`WALLPAPERS`)
# and inserts the catalog row into Cloudflare D1 (`glitter-db`).
#
#   scripts/upload-wallpaper.sh <video> --title "Blue Lagoon" --category "Glitter Originals" \
#     [--creator "Name"] [--creator-url https://…] [--sort 10] [--unpublished]
#
# Requires `npx wrangler@4 login` once.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tail -n 1)/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
kv_namespace_id="${KV_NAMESPACE_ID:-c9eddbf693494b4dbf53e47368b3bd6d}"

video="${1:?usage: upload-wallpaper.sh <video> --title … --category …}"; shift
title="" category="" creator="" creator_url="" sort=0 published=1
while [ $# -gt 0 ]; do
    case "$1" in
        --title) title="$2"; shift 2 ;;
        --category) category="$2"; shift 2 ;;
        --creator) creator="$2"; shift 2 ;;
        --creator-url) creator_url="$2"; shift 2 ;;
        --sort) sort="$2"; shift 2 ;;
        --unpublished) published=0; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$title" ] && [ -n "$category" ] || { echo "--title and --category are required" >&2; exit 2; }

probe="$(swift "$here/wallpaper-tool.swift" probe "$video")"
duration="$(echo "$probe" | jq -r .duration)"
width="$(echo "$probe" | jq -r .width)"
height="$(echo "$probe" | jq -r .height)"
# The Lock Screen only plays Live Photos up to 5 s; longer clips are trimmed in the app, but keep uploads short.
if [ "$(echo "$duration > 5" | bc)" = 1 ]; then
    echo "Video is ${duration}s. Trim it to 5 seconds or less before uploading." >&2
    exit 1
fi

id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
extension="${video##*.}"; extension="$(echo "$extension" | tr '[:upper:]' '[:lower:]')"
video_path="videos/$id.$extension"
thumbnail_path="thumbnails/$id.jpg"
thumbnail="$(mktemp -t thumb).jpg"
sql_file="$(mktemp -t insert).sql"
trap 'rm -f "$thumbnail" "$sql_file"' EXIT

swift "$here/wallpaper-tool.swift" thumbnail "$video" "$thumbnail"
content_type="video/mp4"; [ "$extension" = "mov" ] && content_type="video/quicktime"

kv_put() {
    local key="$1" file="$2" ctype="$3"
    local size etag meta
    size="$(stat -f %z "$file")"
    etag="\"$(shasum -a 256 "$file" | cut -c1-16)\""
    meta="$(jq -nc --arg ct "$ctype" --arg cc "public, max-age=31536000, immutable" --argjson sz "$size" --arg et "$etag" \
        '{contentType: $ct, cacheControl: $cc, size: $sz, etag: $et}')"
    npx --yes wrangler@4 kv key put --namespace-id="$kv_namespace_id" --remote "$key" --path="$file" --metadata="$meta" >/dev/null
}

kv_put "$video_path" "$video" "$content_type"
kv_put "$thumbnail_path" "$thumbnail" "image/jpeg"

ID="$id" TITLE="$title" CATEGORY="$category" VIDEO_PATH="$video_path" THUMB_PATH="$thumbnail_path" \
DURATION="$duration" WIDTH="$width" HEIGHT="$height" CREATOR="$creator" CREATOR_URL="$creator_url" \
SORT="$sort" PUBLISHED="$published" python3 - <<'PY' > "$sql_file"
import os

def q(v):
    if v is None or v == "":
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"

print(
    "INSERT INTO wallpapers (id, kind, title, category, video_path, image_path, thumbnail_path, "
    "duration_seconds, width, height, creator_name, creator_url, is_published, sort_order) VALUES ("
    f"{q(os.environ['ID'])}, 'live', {q(os.environ['TITLE'])}, {q(os.environ['CATEGORY'])}, "
    f"{q(os.environ['VIDEO_PATH'])}, NULL, {q(os.environ['THUMB_PATH'])}, "
    f"{os.environ['DURATION']}, {os.environ['WIDTH']}, {os.environ['HEIGHT']}, "
    f"{q(os.environ['CREATOR'])}, {q(os.environ['CREATOR_URL'])}, {os.environ['PUBLISHED']}, {os.environ['SORT']});"
)
PY

(cd "$repo/cloudflare/api" && npx --yes wrangler@4 d1 execute glitter-db --remote --file="$sql_file" -y >/dev/null)
echo "Added \"$title\" ($category, ${duration}s) as $id"

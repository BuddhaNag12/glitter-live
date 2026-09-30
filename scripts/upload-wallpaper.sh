#!/bin/bash
# Uploads a wallpaper video and its thumbnail to Supabase Storage and adds it to the Explore catalog.
#
#   scripts/upload-wallpaper.sh <video> --title "Blue Lagoon" --category "Glitter Originals" \
#     [--creator "Name"] [--creator-url https://…] [--sort 10] [--unpublished]
#
# Reads credentials from scripts/storage.env (see scripts/storage.env.example).
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH

here="$(cd "$(dirname "$0")" && pwd)"
set -a; . "$here/storage.env"; set +a
export AWS_ACCESS_KEY_ID="$SUPABASE_S3_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$SUPABASE_S3_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION="$SUPABASE_S3_REGION"

video="${1:?usage: upload-wallpaper.sh <video> --title … --category …}"; shift
title="" category="" creator="" creator_url="" sort=0 published=true
while [ $# -gt 0 ]; do
    case "$1" in
        --title) title="$2"; shift 2 ;;
        --category) category="$2"; shift 2 ;;
        --creator) creator="$2"; shift 2 ;;
        --creator-url) creator_url="$2"; shift 2 ;;
        --sort) sort="$2"; shift 2 ;;
        --unpublished) published=false; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$title" ] && [ -n "$category" ] || { echo "--title and --category are required" >&2; exit 2; }

probe="$(swift "$here/wallpaper-tool.swift" probe "$video")"
duration="$(echo "$probe" | jq -r .duration)"
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
trap 'rm -f "$thumbnail"' EXIT

swift "$here/wallpaper-tool.swift" thumbnail "$video" "$thumbnail"
content_type="video/mp4"; [ "$extension" = "mov" ] && content_type="video/quicktime"
aws s3 cp "$video" "s3://$SUPABASE_STORAGE_BUCKET/$video_path" --endpoint-url "$SUPABASE_S3_ENDPOINT" \
    --content-type "$content_type" --cache-control "public, max-age=31536000, immutable" --only-show-errors
aws s3 cp "$thumbnail" "s3://$SUPABASE_STORAGE_BUCKET/$thumbnail_path" --endpoint-url "$SUPABASE_S3_ENDPOINT" \
    --content-type image/jpeg --cache-control "public, max-age=31536000, immutable" --only-show-errors

row="$(jq -n \
    --arg id "$id" --arg title "$title" --arg category "$category" \
    --arg video_path "$video_path" --arg thumbnail_path "$thumbnail_path" \
    --argjson probe "$probe" --arg creator "$creator" --arg creator_url "$creator_url" \
    --argjson sort "$sort" --argjson published "$published" \
    '{id: $id, title: $title, category: $category, video_path: $video_path, thumbnail_path: $thumbnail_path,
      duration_seconds: $probe.duration, width: $probe.width, height: $probe.height,
      creator_name: (if $creator == "" then null else $creator end),
      creator_url: (if $creator_url == "" then null else $creator_url end),
      sort_order: $sort, is_published: $published}')"

curl -sS --fail-with-body -X POST "https://$SUPABASE_PROJECT_REF.supabase.co/rest/v1/wallpapers" \
    -H "apikey: $SUPABASE_SECRET_KEY" -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d "$row" >/dev/null

echo "Added \"$title\" ($category, ${duration}s) as $id"

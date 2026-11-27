#!/bin/bash
# Exports all Supabase Postgres catalog/limits tables (JSON + SQLite seed.sql) and downloads
# every file from the public `wallpapers` Storage bucket into backups/supabase-<date>/.
#
#   scripts/export-supabase.sh [output-dir]
#
# Uses the logged-in `supabase` CLI (`supabase projects api-keys --reveal`) or scripts/storage.env.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
project_ref="${SUPABASE_PROJECT_REF:-jusrioirjfpaocgmsbbv}"
out_dir="${1:-$repo/backups/supabase-$(date +%Y%m%d)}"

if [ -f "$here/storage.env" ]; then
    set -a; . "$here/storage.env"; set +a
    project_ref="${SUPABASE_PROJECT_REF:-$project_ref}"
fi

mkdir -p "$out_dir/storage"

# Resolve key and export tables + generate D1 seed.sql in Python so secret keys stay out of shell args/logs.
SUPABASE_PROJECT_REF="$project_ref" OUT_DIR="$out_dir" python3 - <<'PY'
import json
import os
import subprocess
import urllib.request

project_ref = os.environ["SUPABASE_PROJECT_REF"]
out_dir = os.environ["OUT_DIR"]
secret_key = os.environ.get("SUPABASE_SECRET_KEY", "").strip()

if not secret_key:
    raw = subprocess.check_output(
        ["supabase", "projects", "api-keys", f"--remote={project_ref}", "--reveal"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
    for line in raw.splitlines():
        if line.startswith("{"):
            keys = json.loads(line).get("keys", [])
            for kind in ("secret", "service_role"):
                match = next((k["api_key"] for k in keys if k.get("type") == kind or k.get("name") == kind), None)
                if match and "·" not in match:
                    secret_key = match
                    break
            break

if not secret_key:
    raise SystemExit("Could not find an unmasked Supabase secret/service_role key.")

base_url = f"https://{project_ref}.supabase.co"

def fetch_table(table: str, order: str | None = None):
    rows = []
    offset = 0
    page = 1000
    while True:
        url = f"{base_url}/rest/v1/{table}?select=*"
        if order:
            url += f"&order={order}"
        req = urllib.request.Request(
            url,
            headers={
                "apikey": secret_key,
                "Authorization": f"Bearer {secret_key}",
                "Range": f"{offset}-{offset + page - 1}",
                "Range-Unit": "items",
            },
        )
        with urllib.request.urlopen(req) as resp:
            batch = json.loads(resp.read().decode("utf-8"))
        rows.extend(batch)
        if len(batch) < page:
            return rows
        offset += page

tables = {
    "wallpapers": fetch_table("wallpapers", "sort_order.asc,created_at.desc"),
    "category_covers": fetch_table("category_covers", "category.asc"),
    "ad_rewards": fetch_table("ad_rewards", "created_at.asc"),
    "generation_reports": fetch_table("generation_reports", "created_at.asc"),
}

for name, rows in tables.items():
    with open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2)
    print(f"Exported {name}: {len(rows)} rows")

def sql_val(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"

lines = []
for row in tables["wallpapers"]:
    cols = [
        "id", "kind", "title", "category", "video_path", "image_path", "thumbnail_path",
        "duration_seconds", "width", "height", "creator_name", "creator_url",
        "is_published", "is_featured", "is_category_cover", "sort_order", "created_at",
    ]
    vals = ", ".join(sql_val(row.get(c)) for c in cols)
    lines.append(f"INSERT OR REPLACE INTO wallpapers ({', '.join(cols)}) VALUES ({vals});")

for row in tables["category_covers"]:
    cols = ["category", "image_path", "updated_at"]
    vals = ", ".join(sql_val(row.get(c)) for c in cols)
    lines.append(f"INSERT OR REPLACE INTO category_covers ({', '.join(cols)}) VALUES ({vals});")

for row in tables["ad_rewards"]:
    cols = ["transaction_id", "install_id", "nonce", "created_at", "redeemed_at"]
    vals = ", ".join(sql_val(row.get(c)) for c in cols)
    lines.append(f"INSERT OR REPLACE INTO ad_rewards ({', '.join(cols)}) VALUES ({vals});")

for row in tables["generation_reports"]:
    cols = ["id", "install_id", "prompt", "reason", "created_at"]
    vals = ", ".join(sql_val(row.get(c)) for c in cols)
    lines.append(f"INSERT OR REPLACE INTO generation_reports ({', '.join(cols)}) VALUES ({vals});")

with open(os.path.join(out_dir, "seed.sql"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

# Collect all storage object paths from both Supabase Storage and DB rows.
storage_paths = set()
for folder in ("videos/", "images/", "thumbnails/", "covers/"):
    raw = subprocess.check_output(
        ["supabase", "storage", "ls", f"ss:///wallpapers/{folder}", "--remote", "--experimental", "-r"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
    for line in raw.splitlines():
        if line.startswith("{"):
            for p in json.loads(line).get("paths", []):
                p = p.lstrip("/")
                if p.startswith("wallpapers/"):
                    p = p[len("wallpapers/"):]
                if p and not p.endswith("/"):
                    storage_paths.add(p)

for row in tables["wallpapers"]:
    for key in ("video_path", "image_path", "thumbnail_path"):
        if row.get(key):
            storage_paths.add(row[key])
for row in tables["category_covers"]:
    if row.get("image_path"):
        storage_paths.add(row["image_path"])

sorted_paths = sorted(storage_paths)
with open(os.path.join(out_dir, "storage-paths.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(sorted_paths) + "\n")

print(f"Downloading {len(sorted_paths)} storage files...")
total_bytes = 0
for idx, rel_path in enumerate(sorted_paths, 1):
    dest = os.path.join(out_dir, "storage", rel_path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        total_bytes += os.path.getsize(dest)
        continue
    url = f"{base_url}/storage/v1/object/public/wallpapers/{rel_path}"
    req = urllib.request.Request(url, headers={"apikey": secret_key, "Authorization": f"Bearer {secret_key}"})
    with urllib.request.urlopen(req) as resp, open(dest, "wb") as out_f:
        data = resp.read()
        out_f.write(data)
        total_bytes += len(data)
    if idx % 20 == 0 or idx == len(sorted_paths):
        print(f"  {idx}/{len(sorted_paths)} ({total_bytes / (1024 * 1024):.1f} MB)")

print(f"Backup complete in {out_dir}: {len(sorted_paths)} files, {total_bytes / (1024 * 1024):.1f} MB")
PY

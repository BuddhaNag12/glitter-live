#!/bin/bash
# Uploads backed-up wallpaper files from backups/supabase-<date>/storage/ into the
# Cloudflare Workers KV namespace (`WALLPAPERS`, id c9eddbf693494b4dbf53e47368b3bd6d).
#
#   scripts/copy-to-kv.sh [backup-dir]
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tail -n 1)/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
backup_dir="${1:-$repo/backups/supabase-$(date +%Y%m%d)}"
namespace_id="${KV_NAMESPACE_ID:-c9eddbf693494b4dbf53e47368b3bd6d}"

if [ ! -f "$backup_dir/storage-paths.txt" ]; then
    "$here/export-supabase.sh" "$backup_dir"
fi

# Pack into <= 16 MB JSON batches with base64 values for `wrangler kv bulk put` (fast & low Class-A count).
BACKUP_DIR="$backup_dir" NAMESPACE_ID="$namespace_id" node - <<'NODE'
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const backupDir = process.env.BACKUP_DIR;
const namespaceId = process.env.NAMESPACE_ID;
const paths = readFileSync(join(backupDir, 'storage-paths.txt'), 'utf8')
  .split('\n')
  .map((s) => s.trim())
  .filter(Boolean);

function contentTypeFor(relPath) {
  if (relPath.endsWith('.mp4')) return 'video/mp4';
  if (relPath.endsWith('.mov')) return 'video/quicktime';
  if (relPath.endsWith('.png')) return 'image/png';
  if (relPath.endsWith('.jpg') || relPath.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

const MAX_BATCH_BYTES = 16 * 1024 * 1024;
const tempDir = mkdtempSync(join(tmpdir(), 'kv-bulk-'));
let batch = [];
let batchBytes = 0;
let batchNum = 0;
let uploaded = 0;

function flush() {
  if (batch.length === 0) return;
  batchNum += 1;
  const jsonPath = join(tempDir, `batch-${batchNum}.json`);
  writeFileSync(jsonPath, JSON.stringify(batch));
  execFileSync(
    'npx',
    ['--yes', 'wrangler@4', 'kv', 'bulk', 'put', jsonPath, `--namespace-id=${namespaceId}`, '--remote'],
    { stdio: 'inherit' },
  );
  uploaded += batch.length;
  console.log(`Uploaded batch ${batchNum}: ${uploaded}/${paths.length} files`);
  batch = [];
  batchBytes = 0;
}

try {
  for (const relPath of paths) {
    const buf = readFileSync(join(backupDir, 'storage', relPath));
    const etag = `"${createHash('sha256').update(buf).digest('hex').slice(0, 16)}"`;
    const b64 = buf.toString('base64');
    const item = {
      key: relPath,
      value: b64,
      base64: true,
      metadata: {
        contentType: contentTypeFor(relPath),
        cacheControl: 'public, max-age=31536000, immutable',
        size: buf.byteLength,
        etag,
      },
    };
    if (batch.length > 0 && batchBytes + b64.length > MAX_BATCH_BYTES) {
      flush();
    }
    batch.push(item);
    batchBytes += b64.length;
  }
  flush();
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
NODE

#!/usr/bin/env bash
# restore-test.sh — prove the newest backup can be restored: check its checksum, unpack it into a temporary
# directory and compare it file by file with the live volume. Exit 0 = restore works, 1 = it doesn't.
# Usage: ./restore-test.sh      Env: BACKUP_DIR (default ./backups), VOLUME (default homelab_site-data)
set -euo pipefail

VOLUME="${VOLUME:-homelab_site-data}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$0")/backups}"

newest=$(find "$BACKUP_DIR" -maxdepth 1 -name 'site-*.tar.gz' 2>/dev/null | sort | tail -n 1 || true)
[ -n "$newest" ] || { echo "FAIL: no backups in $BACKUP_DIR" >&2; exit 1; }
echo "testing: $newest"

# 1. The archive must be exactly what backup.sh wrote.
(cd "$(dirname "$newest")" && sha256sum --quiet -c "$(basename "$newest").sha256") \
  || { echo "FAIL: checksum mismatch, the archive is damaged" >&2; exit 1; }

# 2. It must unpack.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/restored" "$tmp/live"
tar xzf "$newest" -C "$tmp/restored" || { echo "FAIL: archive does not unpack" >&2; exit 1; }

# 3. Restored files must match the live volume (copied out the same way the backup was made).
docker run --rm --security-opt label=disable -v "$VOLUME":/data:ro alpine:3.20 tar cf - -C /data . | tar xf - -C "$tmp/live"
if diff -rq "$tmp/restored" "$tmp/live" > "$tmp/diff.txt"; then
  echo "OK: $(find "$tmp/restored" -type f | wc -l) file(s) restored and identical to the live volume"
else
  echo "WARN: restore works, but these files changed since this backup:"
  sed -e "s#$tmp/restored#backup#" -e "s#$tmp/live#live#" -e "s/^/  /" "$tmp/diff.txt"
fi

#!/usr/bin/env bash
# backup.sh — archive the site volume to backups/site-YYYYmmdd-HHMMSS.tar.gz (+ .sha256), keep the newest KEEP.
# Usage: ./backup.sh            Env: BACKUP_DIR (default ./backups), KEEP (default 3), VOLUME (default homelab_site-data)
set -euo pipefail

VOLUME="${VOLUME:-homelab_site-data}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$0")/backups}"
KEEP="${KEEP:-3}"

docker volume inspect "$VOLUME" >/dev/null 2>&1 || { echo "volume $VOLUME not found — is the stack up? (docker compose up -d)" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

stamp=$(date +%Y%m%d-%H%M%S)
archive="$BACKUP_DIR/site-$stamp.tar.gz"
trap 'rm -f "$archive.tmp"' EXIT   # never leave a half-written archive behind
# The archive is streamed out of a throwaway container (volume mounted read-only), so no host folder is mounted.
# label=disable: on SELinux hosts (Fedora/RHEL) the helper may otherwise not read a volume another container uses.
docker run --rm --security-opt label=disable -v "$VOLUME":/data:ro alpine:3.20 tar czf - -C /data . > "$archive.tmp"
mv "$archive.tmp" "$archive"   # only complete archives get the final name
(cd "$BACKUP_DIR" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "backup: $archive ($(du -h "$archive" | cut -f1))"

# Retention: delete everything but the newest $KEEP archives (names sort by date).
mapfile -t old < <(find "$BACKUP_DIR" -maxdepth 1 -name 'site-*.tar.gz' | sort | head -n -"$KEEP")
for f in "${old[@]}"; do
  rm -f -- "$f" "$f.sha256"
  echo "removed old backup: $f"
done

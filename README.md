# homelab-docker-monitoring-notes

A small, one-command home lab: an nginx service in Docker Compose with a healthcheck, a **backup script with
retention**, and a **restore test**, because a backup only counts once you've restored it. Written up as a short ops runbook.

## Quick start

```bash
docker compose up -d --wait      # start; --wait returns once the healthcheck reports "healthy"
docker compose ps                # STATUS: Up … (healthy)
curl -s localhost:8080 | head -4 # the site (bound to 127.0.0.1 only)

./backup.sh                      # backups/site-YYYYmmdd-HHMMSS.tar.gz + .sha256, keeps the newest 3
./restore-test.sh                # checksum → unpack → compare with the live volume
```

```text
$ ./backup.sh
backup: ./backups/site-20261108-234944.tar.gz (4.0K)
$ ./restore-test.sh
testing: ./backups/site-20261108-234944.tar.gz
OK: 2 file(s) restored and identical to the live volume
```

| Situation | `restore-test.sh` says | Exit code |
|---|---|---|
| Backup is good and matches the live site | `OK: … identical to the live volume` | 0 |
| Backup is good, the site changed since | `WARN: … these files changed since this backup` + file list | 0 |
| Archive damaged (checksum mismatch) | `FAIL: checksum mismatch, the archive is damaged` | 1 |
| No backups at all | `FAIL: no backups in …` | 1 |

Settings come from environment variables: `BACKUP_DIR` (default `./backups`), `KEEP` (default 3) and `VOLUME` (default `homelab_site-data`).

## How the backup works

- The volume is archived by a throwaway `alpine` container that mounts it **read-only** and streams the tar to
  stdout. No host folder is mounted into a container, so there are no file-permission problems.
- The archive is written to a `.tmp` file and renamed only when complete. A failed run leaves nothing behind.
- A SHA-256 checksum is stored next to each archive. The restore test checks it before unpacking.
- On SELinux hosts (Fedora/RHEL) the helper runs with `--security-opt label=disable`. Without it, it isn't allowed to read a
  volume that another container is using (found while testing on Fedora).

## Nightly backups with a systemd timer

Copy the project to `/opt/homelab`, then add these two units to `/etc/systemd/system/`:

```ini
# homelab-backup.service
[Unit]
Description=Back up the homelab site volume
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/homelab
ExecStart=/opt/homelab/backup.sh
```

```ini
# homelab-backup.timer
[Unit]
Description=Nightly homelab backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer
systemctl list-timers homelab-backup.timer      # shows the next run
```

(`Persistent=true` runs a missed backup at the next boot if the machine was off at 03:00.)
Cron alternative: `0 3 * * * cd /opt/homelab && ./backup.sh >> backup.log 2>&1`

## Reaching the box over SSH (key login)

```bash
ssh-keygen -t ed25519 -C "homelab"            # on your laptop
ssh-copy-id user@homelab.local                # installs the public key on the server
```

```text
# ~/.ssh/config on the laptop
Host homelab
    HostName homelab.local
    User user
    IdentityFile ~/.ssh/id_ed25519
```

Then `ssh homelab`. Once key login works, set `PasswordAuthentication no` in `/etc/ssh/sshd_config` on the server.

## What I'd use on Windows Server / Hyper-V

I haven't run these myself; this is how the same ideas map across:

| Here | Windows world |
|---|---|
| Docker Compose service | IIS site, or a Hyper-V VM per service |
| `backup.sh` + systemd timer | Windows Server Backup or Veeam, scheduled with Task Scheduler |
| `restore-test.sh` | a scheduled test restore into an isolated VM |
| healthcheck | Windows service recovery options / monitoring (e.g. PRTG, Zabbix agent) |
| SSH keys | RDP with Network Level Authentication, or OpenSSH Server on Windows |

## Testing

CI (`.github/workflows/ci.yml`) runs the whole cycle on every push: start → healthy → backup → restore test →
change the site (expects WARN) → retention keeps 3 → a corrupted archive must fail.
Both scripts are ShellCheck-clean.

## License

[MIT](LICENSE)

## AI usage

This project was created with the help of AI. The code, tests and documentation were written with [Claude Code](https://claude.com/claude-code) (Anthropic), then reviewed, run and verified by me.

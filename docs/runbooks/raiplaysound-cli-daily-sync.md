# RaiPlaySound CLI Daily Sync Runbook

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [Runtime Shape](#runtime-shape)
- [Install or Update](#install-or-update)
- [Config Management](#config-management)
- [Operate](#operate)
- [Validation](#validation)
- [Rollback](#rollback)
- [Evidence Log](#evidence-log)

## Purpose

Operate the PiServ `raiplaysound-cli-daily-sync` scheduled workload that writes
RaiPlaySound podcast output directly into the pCloud-backed podcast target.

## Status

Installed and validated on PiServ on 2026-07-08. The user timer is active and
the first manual service run completed successfully with direct writes to
pCloud. The existing live config now includes mail-summary keys and the email
summary dry-run path has been validated without sending.

## Runtime Shape

| Item | Value |
| --- | --- |
| Runtime user | `operator` |
| CLI version | `2.5.0` |
| Source revision | `55dfb29c0c15cc30c603338072261fabf5e52fe4` |
| Source path | `/opt/raiplaysound-cli` |
| Command | `/home/operator/.local/bin/raiplaysound-cli-daily-sync` |
| Config | `/home/operator/.config/raiplaysound-cli/piserv-daily-sync.conf` |
| Log | `/home/operator/.local/state/raiplaysound-cli/daily-sync.log` |
| Service | `raiplaysound-cli-daily-sync.service` |
| Timer | `raiplaysound-cli-daily-sync.timer` |
| Schedule | Daily at 08:00 local time, randomized up to five minutes |
| Target | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |
| Storage model | Direct write to the pCloud FUSE mount |

The service runs the pCloud health helper as `ExecStartPre`. If the pCloud
service, mount, target directory, or write/read/delete check fails, the sync
does not start.

New PiServ configs include non-secret email wiring that sends to local recipient
`root` through the system `msmtp` config. The existing live config has been
updated with the same non-secret keys.

## Install or Update

Run from the PiServ repository root:

```sh
ansible-playbook ansible/playbooks/raiplaysound-cli-daily-sync.yml
```

The playbook installs Debian dependencies, checks out the pinned CLI source,
runs the upstream `make install` path for `operator`, creates the PiServ config
when missing, installs the pCloud health helper, and manages the user
service/timer.

## Config Management

PiServ uses create-only config management:

| Role variable | PiServ value | Effect |
| --- | --- | --- |
| `raiplaysound_cli_config_mode` | `create` | Create the config from role defaults when missing and preserve later direct edits |

Edit the active config directly on PiServ:

```sh
ssh operator@piserv.example.com \
  'nano ~/.config/raiplaysound-cli/piserv-daily-sync.conf'
```

After editing, validate the next run manually:

```sh
ssh operator@piserv.example.com \
  'systemctl --user start raiplaysound-cli-daily-sync.service'
```

If the config file is deliberately deleted, the next playbook run recreates it
from the `raiplaysound_cli` role defaults plus PiServ's non-secret partial
overrides for the podcast target, RSS base URL, and local mail summary wiring.

When overrides are needed, define only changed keys in `raiplaysound_cli_config`.
The role merges those partial values with `raiplaysound_cli_config_defaults`.

The PiServ config includes these mail keys:

```text
EMAIL_TO="root"
EMAIL_CONFIG="/etc/msmtprc"
EMAIL_FROM="operator@example.com"
EMAIL_FROM_NAME="PiServ RaiPlaySound"
EMAIL_SUBJECT_PREFIX="[PiServ raiplaysound-cli]"
MSMTP_BIN="/usr/local/bin/msmtp-system"
```

## Operate

Check the timer:

```sh
ssh operator@piserv.example.com \
  'systemctl --user list-timers --all | grep raiplaysound || true'
```

Run the service manually:

```sh
ssh operator@piserv.example.com \
  'systemctl --user start raiplaysound-cli-daily-sync.service'
```

Inspect service status:

```sh
ssh operator@piserv.example.com \
  'systemctl --user status raiplaysound-cli-daily-sync.service --no-pager'
```

Follow the sync log:

```sh
ssh operator@piserv.example.com \
  'tail -f ~/.local/state/raiplaysound-cli/daily-sync.log'
```

Verify pCloud health before a run:

```sh
scripts/check-pcloudcc-health.sh
```

## Validation

Expected successful service result:

```text
Process: ExecStartPre=...check-pcloudcc-health-remote.sh (status=0/SUCCESS)
Process: ExecStart=...raiplaysound-cli-daily-sync ... (status=0/SUCCESS)
```

First validated direct-write log ending before mail wiring:

```text
Favourites run completed: done=10, errors=0
EMAIL_TO is not configured; skipping email summary.
```

The first validated direct-write run wrote one new `seigradi` audio file and
refreshed metadata, feeds, cover assets, and the target index under the pCloud
mount.

Current email-summary validation uses the installed Python environment to call
only the mail-summary path with `dry_run=True`; it does not start a podcast
download and does not send email.

## Rollback

Stop and disable the timer:

```sh
ssh operator@piserv.example.com \
  'systemctl --user disable --now raiplaysound-cli-daily-sync.timer'
```

Remove the user units if deliberately decommissioning the workload:

```sh
ssh operator@piserv.example.com \
  'rm -f ~/.config/systemd/user/raiplaysound-cli-daily-sync.{service,timer}'
ssh operator@piserv.example.com 'systemctl --user daemon-reload'
```

Rollback does not delete downloaded podcast files.

## Evidence Log

| Date | Check | Result |
| --- | --- | --- |
| 2026-07-08 | Install playbook | Passed; CLI, config, service, and timer installed |
| 2026-07-08 | Timer | Active and waiting for the next 08:00 run |
| 2026-07-08 | pCloud preflight | Passed with `pcloudcc_health=ok` |
| 2026-07-08 | Manual service run | Passed with `done=10`, `errors=0` |
| 2026-07-08 | Direct-write proof | New `seigradi` `.m4a` written under the pCloud target |
| 2026-07-08 | Email wiring | Existing live config now uses local `root` and `/usr/local/bin/msmtp-system` |
| 2026-07-08 | Email dry run | `send_email_summary(..., dry_run=True)` returned `0` without sending |

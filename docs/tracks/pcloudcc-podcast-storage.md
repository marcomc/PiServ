# pCloud `pcloudcc` Podcast Storage Track

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [References](#references)
- [Inputs](#inputs)
- [Scope](#scope)
- [Non-Goals](#non-goals)
- [Implementation Phases](#implementation-phases)
- [Validation Gates](#validation-gates)
- [Automation Scope](#automation-scope)
- [Rollback](#rollback)
- [Open Items](#open-items)
- [Evidence Log](#evidence-log)

## Purpose

Track the live implementation work needed to make PiServ write scheduled
RaiPlaySound podcast output to pCloud through the official `pcloudcc` FUSE
mount.

## Status

Ready for live build validation. Do not enable scheduled podcast writes until
all validation gates in this track pass on PiServ.

## References

| Document | Purpose |
| --- | --- |
| [Decision 0003](../decisions/0003-pcloud-backed-podcast-storage.md) | Accepted storage backend and target paths |
| [pCloud runbook](../runbooks/pcloudcc-storage.md) | Manual validation and health-check commands |

## Inputs

| Item | Value |
| --- | --- |
| Server | `operator@piserv.example.com` / `192.0.2.181` |
| Runtime user | `operator` |
| Hardware | Raspberry Pi 5, 4 GB RAM, 128 GB NVMe |
| OS target | Raspberry Pi OS / Debian `arm64` |
| pCloud account email | Operator-provided; do not store in docs |
| pCloud data region | European Union |
| pCloud password | Manual operator entry only |
| Mount root | `/mnt/pcloud` |
| Podcast target | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |
| Producer workload | `raiplaysound-cli-daily-sync` |
| Initial credential bootstrap | `pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -m /mnt/pcloud` |

## Scope

- Build or install the official `pcloudcc` console client on PiServ.
- Validate EU-region login and saved local credential behavior.
- Validate the `/mnt/pcloud` FUSE mount.
- Validate write, read, delete, and external visibility for the podcast target.
- Add systemd startup only after the manual mount behaves correctly.
- Convert proven live steps into Ansible and small shell health checks.
- Gate scheduled `raiplaysound-cli` runs on pCloud mount health.

## Non-Goals

- Do not configure pCloud Drive AppImage for the scheduled podcast pipeline.
- Do not depend on pCloud rsync support.
- Do not create or manage a dedicated folder-scoped pCloud account yet.
- Do not store the pCloud password in this repository, Ansible, systemd, shell
  history, or environment files.
- Do not enable production scheduled writes before reboot validation passes.

## Implementation Phases

| Phase | Task | Done When |
| --- | --- | --- |
| 1 | Reconfirm live baseline | SSH, sudo, OS, arch, FUSE, `/dev/fuse`, and systemd state are captured |
| 2 | Install build prerequisites | Required Debian packages are installed and documented |
| 3 | Build official `pcloudcc` | Binary path, version, source revision, and install method are recorded |
| 4 | Prepare mount point | `/mnt/pcloud` exists, is owned for the selected runtime model, and is empty before mount |
| 5 | Manual credential bootstrap | Operator enters the password with `-p -s`; no password appears in files we manage |
| 6 | Validate EU-region behavior | Login succeeds for the European Union account or the exact extra setting is identified |
| 7 | Validate mount | `findmnt --mountpoint /mnt/pcloud` reports the expected FUSE mount |
| 8 | Validate podcast path | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` exists and is writable |
| 9 | Validate write round trip | Test file can be written, read, removed, and observed from another pCloud client |
| 10 | Add systemd startup | Service starts without a password on the command line or in unit files |
| 11 | Validate reboot recovery | Reboot returns PiServ to a mounted and writable pCloud state |
| 12 | Integrate workload | `raiplaysound-cli-daily-sync` writes only after the pCloud preflight passes |
| 13 | Automate | Ansible reproduces the non-secret setup and validates the mount health check |

## Validation Gates

| Gate | Command or Check | Required Result |
| --- | --- | --- |
| Build | `command -v pcloudcc && pcloudcc -h` | Installed client prints usage |
| Mount | `findmnt --mountpoint /mnt/pcloud` | Mount is present and backed by `pcloudcc` |
| Target directory | `test -d "/mnt/pcloud/My Music/Podcasts/raiplaypodcast"` | Directory exists |
| Target write | `test -w "/mnt/pcloud/My Music/Podcasts/raiplaypodcast"` | Directory is writable |
| Round trip | Write, read, and delete `.piserv-write-test` | Contents match and cleanup succeeds |
| External visibility | Check from Mac pCloud client or web UI | Test file appears before deletion |
| Secret hygiene | Inspect unit files, Ansible vars, shell scripts, and docs | Password is absent |
| Reboot | Reboot PiServ and rerun mount/write checks | Mount recovers without manual shell state |
| Workload | Run non-destructive `raiplaysound-cli` test | Output lands only in the target path |

## Automation Scope

Automate only after the matching manual step has passed on PiServ.

| Component | Automation Target |
| --- | --- |
| Build prerequisites | Ansible package tasks |
| Source checkout/build | Idempotent Ansible role or task file pinned to a source revision |
| Mount point | Ansible file task |
| Credential bootstrap | Manual runbook step only |
| systemd startup | Unit or user unit without password material |
| pCloud health check | Small shell script plus Ansible validation |
| Scheduled workload dependency | Timer/service preflight or wrapper script |
| Disaster recovery | Runbook section plus playbook entry point |

## Rollback

Use rollback when the mount is unhealthy, systemd loops, or scheduled writes
would risk partial output.

```sh
systemctl --user stop pcloudcc.service
fusermount3 -u /mnt/pcloud
findmnt --mountpoint /mnt/pcloud || true
```

If systemd is implemented as a system service instead of a user service, use
the matching `sudo systemctl stop ...` command documented during that phase.

Do not delete saved `pcloudcc` credentials during ordinary rollback. Remove
them only when deliberately deauthorizing PiServ from pCloud.

## Open Items

- Confirm exact Debian package list needed for Raspberry Pi OS / Debian
  `arm64`.
- Confirm whether source-built `pcloudcc` needs explicit EU-region settings.
- Decide user service versus system service after credential and mount behavior
  are observed.
- Decide whether completed media should write directly to the mount or stage on
  local NVMe before copy.
- Define the final scheduled `raiplaysound-cli` timer/service shape.

## Evidence Log

| Date | Step | Result | Evidence |
| --- | --- | --- | --- |
| 2026-07-07 | Track created | Ready for live build validation | This document |

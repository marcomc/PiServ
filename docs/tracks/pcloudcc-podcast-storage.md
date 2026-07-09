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

Client install and install automation are complete, including a CLI patch that
adds TOTP and recovery-code prompts. Manual credential bootstrap with the real
pCloud account, EU-region login validation, mount validation, and podcast
target write validation have passed. User-scoped systemd startup and saved-auth
service restart have passed. Reboot recovery, external visibility, and
repeatable health-check automation have passed. The scheduled RaiPlaySound
workload is installed, health-check gated, and validated with direct writes.

## Progress Snapshot

| Area | Status | Evidence |
| --- | --- | --- |
| Live client install | Done | `/usr/local/bin/pcloudcc` prints `pCloud console client v.2.0.1` |
| Install automation | Done | `ansible/playbooks/pcloudcc-install.yml` reports `changed=0` on repeat run |
| Galaxy-ready role shape | Done | `ansible/roles/pcloudcc/` has metadata, argument specs, docs, tests, and license |
| Version pin | Done | Role default `pcloudcc_version` is `2.0.1`; source revision remains pinned separately |
| TOTP CLI patch | Done | `pcloudcc -h` exposes `--trustdevice` and `--recoverycode` |
| Credential bootstrap | Done | TOTP login succeeded and reached `READY` |
| pCloud mount validation | Done | `/mnt/pcloud` is mounted from `pCloud.fs` |
| Podcast target write test | Done | `.piserv-write-test` write/read/delete passed |
| Credential storage audit | Done | `~operator/.pcloud` hardened to `0700`; DB files hardened to `0600`; no `pass` key present |
| User service startup | Done | `pcloudcc.service` starts with `/usr/local/bin/pcloudcc -m /mnt/pcloud` |
| Service restart | Done | Stop/start remounted `/mnt/pcloud` without email, password, or TOTP |
| Reboot recovery | Done | Reboot changed boot ID and `/mnt/pcloud` remounted automatically |
| External visibility | Done | PiServ marker appeared under the Mac pCloud Drive target path |
| Health-check automation | Done | SSH wrapper and Ansible playbook both report `pcloudcc_health=ok` |
| Podcast workload integration | Done | Manual systemd service run completed with `done=10`, `errors=0` |

## References

| Document | Purpose |
| --- | --- |
| [Decision 0003](../decisions/0003-pcloud-backed-podcast-storage.md) | Accepted storage backend and target paths |
| [Decision 0006](../decisions/0006-raiplaysound-direct-write-scheduling.md) | Accepted direct-write scheduled workload |
| [pCloud runbook](../runbooks/pcloudcc-storage.md) | Manual validation and health-check commands |
| [RaiPlaySound runbook](../runbooks/raiplaysound-cli-daily-sync.md) | Scheduled workload operation |

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
| Initial credential bootstrap | `pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -t -m /mnt/pcloud` |

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
- Do not run production scheduled writes without the pCloud health check.

## Implementation Phases

| Phase | Task | Done When |
| --- | --- | --- |
| 1 | Reconfirm live baseline | SSH, sudo, OS, arch, FUSE, `/dev/fuse`, and systemd state are captured |
| 2 | Install build prerequisites | Required Debian packages are installed and documented |
| 3 | Build official `pcloudcc` | Binary path, client version, source revision, and install method are recorded |
| 4 | Prepare mount point | `/mnt/pcloud` exists, is owned for the selected runtime model, and is empty before mount |
| 5 | Patch TOTP bootstrap | CLI exposes TOTP and recovery-code prompt support |
| 6 | Manual credential bootstrap | Done; operator entered password and TOTP interactively |
| 7 | Validate EU-region behavior | Done; login succeeded for the European Union account |
| 8 | Validate mount | Done; `findmnt --mountpoint /mnt/pcloud` reports `pCloud.fs` |
| 9 | Validate podcast path | Done; `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` exists and is writable |
| 10 | Validate write round trip | Done for local write/read/delete and external visibility |
| 11 | Add systemd startup | Done; user service starts without email, password, or TOTP in unit files |
| 12 | Validate reboot recovery | Done; reboot returns PiServ to a mounted and writable pCloud state |
| 13 | Integrate workload | Done; `raiplaysound-cli-daily-sync` writes only after the pCloud preflight passes |
| 14 | Automate | Done for install, credential hardening, user service, health checks, and scheduled workload |

## Validation Gates

| Gate | Command or Check | Required Result |
| --- | --- | --- |
| Build | `command -v pcloudcc && pcloudcc -h` | Installed client prints usage |
| Mount | `findmnt --mountpoint /mnt/pcloud` | Mount is present and backed by `pcloudcc` |
| Target directory | `test -d "/mnt/pcloud/My Music/Podcasts/raiplaypodcast"` | Directory exists |
| Target write | `test -w "/mnt/pcloud/My Music/Podcasts/raiplaypodcast"` | Directory is writable |
| Round trip | Write, read, and delete `.piserv-write-test` | Contents match and cleanup succeeds |
| External visibility | Check from Mac pCloud client or web UI | Test file appears in pCloud-backed storage |
| Secret hygiene | Inspect unit files, Ansible vars, shell scripts, and docs | Password is absent |
| Credential file mode | `find /home/operator/.pcloud -maxdepth 2 -printf ...` | Directories `0700`, files `0600` |
| Saved password absence | Inspect `setting` keys in `data.db` without values | `auth` and `saveauth` present; `pass` absent |
| Reboot | Reboot PiServ and rerun mount/write checks | Mount recovers without manual shell state |
| Health script | `scripts/check-pcloudcc-health.sh` | `pcloudcc_health=ok` |
| Health playbook | `ansible-playbook ansible/playbooks/pcloudcc-health-check.yml` | `pcloudcc_health=ok` |
| Workload | Run `raiplaysound-cli-daily-sync.service` | Output lands only in the target path |

## Automation Scope

Automate only after the matching manual step has passed on PiServ.

| Component | Automation Target |
| --- | --- |
| Build prerequisites | Ansible package tasks |
| Source checkout/build | Idempotent Ansible role or task file pinned to a source revision |
| Mount point | Ansible file task |
| Credential bootstrap | Manual runbook step only |
| systemd startup | User unit without password material |
| pCloud health check | Small shell script plus Ansible validation |
| Scheduled workload dependency | User systemd service with pCloud health preflight |
| Disaster recovery | Runbook section plus playbook entry point |

## Rollback

Use rollback when the mount is unhealthy, systemd loops, or scheduled writes
would risk partial output.

```sh
systemctl --user stop pcloudcc.service
fusermount -u /mnt/pcloud
findmnt --mountpoint /mnt/pcloud || true
```

Do not delete saved `pcloudcc` credentials during ordinary rollback. Remove
them only when deliberately deauthorizing PiServ from pCloud; see the
[deauthorization runbook](../runbooks/pcloudcc-storage.md#deauthorization).

## Open Items

- Monitor the first unattended 08:00 timer run.

## Evidence Log

| Date | Step | Result | Evidence |
| --- | --- | --- | --- |
| 2026-07-07 | Track created | Ready for live build validation | This document |
| 2026-07-08 | Live client install | Passed | `/usr/local/bin/pcloudcc`; source revision `980d2cadf670f1b14642c7dbe015f95bd2306175` |
| 2026-07-08 | Install automation | Passed | `ansible-playbook ansible/playbooks/pcloudcc-install.yml` ended with `changed=0` on repeat run |
| 2026-07-08 | Version default | Passed | `pcloudcc_version` defaults to `2.0.1`; expected output is derived from that value |
| 2026-07-08 | First login with TOTP-enabled account | Blocked | pCloud returned API error `2297 Two factor authentication required`; `/mnt/pcloud` remained unmounted |
| 2026-07-08 | CLI TOTP patch | Passed | Rebuilt `pcloudcc`; `pcloudcc -h` exposes `--trustdevice` and `--recoverycode` |
| 2026-07-08 | TOTP login and mount | Passed | `pcloudcc` reached `READY`; `/mnt/pcloud` mounted as `pCloud.fs` |
| 2026-07-08 | Podcast target write test | Passed | `.piserv-write-test` write/read/delete passed under `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |
| 2026-07-08 | User service install | Passed | `pcloudcc.service` enabled and active for `operator`; `Linger=yes` |
| 2026-07-08 | Credential storage audit | Passed | `~operator/.pcloud` mode `0700`; DB files mode `0600`; `auth` present; `pass` absent |
| 2026-07-08 | Saved-auth service restart | Passed | Stop/start remounted `/mnt/pcloud` without interactive login |
| 2026-07-08 | Reboot recovery | Passed | Boot ID changed; `pcloudcc.service` active; `/mnt/pcloud` remounted as `pCloud.fs` |
| 2026-07-08 | External visibility | Passed | `.piserv-cloud-visibility-20260708-121151.txt` appeared in the Mac pCloud Drive path |
| 2026-07-08 | Health-check automation | Passed | SSH wrapper and Ansible playbook both returned `pcloudcc_health=ok` |
| 2026-07-08 | RaiPlaySound timer install | Passed | `raiplaysound-cli-daily-sync.timer` active and waiting |
| 2026-07-08 | RaiPlaySound direct-write service run | Passed | Manual run ended `done=10`, `errors=0`; one new `seigradi` audio file written |

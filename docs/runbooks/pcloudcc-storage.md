# pCloud Console Client Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [Preconditions](#preconditions)
- [Target Shape](#target-shape)
- [Validation Plan](#validation-plan)
- [Health Checks](#health-checks)
- [Automation Follow-Up](#automation-follow-up)

## Purpose

Validate the official `pcloudcc` console client as PiServ's pCloud-backed
storage layer for scheduled podcast-producing jobs.

## Status

Planned. Do not enable scheduled podcast jobs until the mount and write tests
pass on PiServ.

## Preconditions

- PiServ is reachable as `operator@piserv.example.com`.
- `operator` has sudo access.
- pCloud credentials are available out of band.
- The target pCloud remote folder is decided.
- No pCloud credentials are written into this repository.

## Target Shape

| Item | Decision |
| --- | --- |
| Backend | Official `pcloudcc` console client |
| Mount type | FUSE |
| Service manager | systemd |
| Runtime user | `operator` |
| Podcast producer | `raiplaysound-cli-daily-sync` |
| Required preflight | Mount present, writable, and round-trip file test passes |

## Validation Plan

1. Install build prerequisites on PiServ.
2. Build `pcloudcc` from the official pCloud console-client source.
3. Start `pcloudcc` manually with an explicit mount point.
4. Confirm the mount appears in `findmnt`.
5. Write, read, and delete a small test file through the mount.
6. Confirm the file appears in pCloud from another client.
7. Wrap the mount in systemd.
8. Reboot PiServ and confirm the mount recovers without manual shell state.
9. Run `raiplaysound-cli-daily-sync` against a non-destructive test folder.

## Health Checks

Minimum checks before any scheduled podcast job writes output:

```sh
findmnt --mountpoint /path/to/pcloud-mount
test -w /path/to/pcloud-mount
test_payload="piserv-pcloudcc-$$(date +%s)"
printf '%s\n' "${test_payload}" > /path/to/pcloud-mount/.piserv-write-test
grep -Fx "${test_payload}" /path/to/pcloud-mount/.piserv-write-test
rm -f /path/to/pcloud-mount/.piserv-write-test
```

Replace `/path/to/pcloud-mount` with the final mount point after validation.

## Automation Follow-Up

- Add Ansible tasks for build prerequisites.
- Add Ansible tasks for building or installing `pcloudcc`.
- Add a systemd unit for the `pcloudcc` mount.
- Add a preflight script for mount and write validation.
- Make `raiplaysound-cli` scheduling depend on the pCloud health check.
- Document credential provisioning without committing secrets.

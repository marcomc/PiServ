# pCloud Console Client Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [Preconditions](#preconditions)
- [Target Shape](#target-shape)
- [Credential Bootstrap](#credential-bootstrap)
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
- The pCloud account email is supplied by the operator during setup.
- The pCloud data region is European Union.
- The pCloud password is provided interactively during first login.
- No pCloud credentials are written into this repository.

## Target Shape

| Item | Decision |
| --- | --- |
| Backend | Official `pcloudcc` console client |
| Mount type | FUSE |
| Service manager | systemd |
| Runtime user | `operator` |
| pCloud account email | Operator-provided; do not store in docs |
| pCloud data region | European Union |
| Mount root | `/mnt/pcloud` |
| Podcast target | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |
| Podcast producer | `raiplaysound-cli-daily-sync` |
| Credential bootstrap | Manual first login with `pcloudcc -p -s` as `operator` |
| Required preflight | Mount present, writable, and round-trip file test passes |
| Account scope | Existing user pCloud account with full pCloud access |

## Credential Bootstrap

The official `pcloudcc` client documents `-s` / `--savepassword` as the
password persistence mechanism. It does not document a password config file or
password environment variable.

Run first login manually on PiServ as `operator`:

```sh
sudo install -d -o operator -g operator -m 0755 /mnt/pcloud
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -m /mnt/pcloud
```

`pcloudcc` prompts for the pCloud password and saves it in the local pCloud
client database for the Unix user running the command. Do not put the password
in the command line, a systemd unit, an environment file, Ansible variables, or
this repository.

After first login succeeds, non-interactive startup should pass only the
account email and mount point:

```sh
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -d -m /mnt/pcloud
```

The upstream source defines the POSIX pCloud data directory as `.pcloud`, the
POSIX database name as `.pclouddb`, and the cache folder as `Cache`.
Validate the actual files and permissions on PiServ after first login.

Because the pCloud account is EU-region, validate live whether the source-built
client needs extra region configuration before automating the service. Do not
bake region-specific environment into Ansible until the PiServ build proves it.

## Validation Plan

1. Install build prerequisites on PiServ.
2. Build `pcloudcc` from the official pCloud console-client source.
3. Run the manual first login with `-p -s` as `operator`.
4. Start `pcloudcc` manually with `/mnt/pcloud` as the mount point.
5. Confirm the mount appears in `findmnt`.
6. Confirm `My Music/Podcasts/raiplaypodcast` exists under the mount.
7. Write, read, and delete a small test file through the podcast target.
8. Confirm the file appears in pCloud from another client.
9. Wrap the mount in systemd without passing the pCloud password.
10. Reboot PiServ and confirm the mount recovers without manual shell state.
11. Run `raiplaysound-cli-daily-sync` against a non-destructive test folder.

## Health Checks

Minimum checks before any scheduled podcast job writes output:

```sh
target="/mnt/pcloud/My Music/Podcasts/raiplaypodcast"
findmnt --mountpoint /mnt/pcloud
test -d "${target}"
test -w "${target}"
test_payload="piserv-pcloudcc-$$(date +%s)"
printf '%s\n' "${test_payload}" > "${target}/.piserv-write-test"
grep -Fx "${test_payload}" "${target}/.piserv-write-test"
rm -f "${target}/.piserv-write-test"
```

The target path contains a space in `My Music`; quote it in shell commands.

## Automation Follow-Up

- Add Ansible tasks for build prerequisites.
- Add Ansible tasks for building or installing `pcloudcc`.
- Add a systemd unit for the `pcloudcc` mount.
- Add a preflight script for mount and write validation.
- Make `raiplaysound-cli` scheduling depend on the pCloud health check.
- Keep password bootstrap manual; automate only non-secret service settings.
- Validate saved credential file locations and permissions after first login.

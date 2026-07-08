# pCloud Console Client Storage Runbook

## Table of Contents

- [Purpose](#purpose)
- [Status](#status)
- [Preconditions](#preconditions)
- [Target Shape](#target-shape)
- [Client Installation](#client-installation)
- [Credential Bootstrap](#credential-bootstrap)
- [Credential Storage and Session Behavior](#credential-storage-and-session-behavior)
- [Validation Plan](#validation-plan)
- [Health Checks](#health-checks)
- [Automation Follow-Up](#automation-follow-up)

## Purpose

Validate the official `pcloudcc` console client as PiServ's pCloud-backed
storage layer for scheduled podcast-producing jobs.

## Status

Client installation is complete on PiServ, including a local CLI patch that
adds TOTP and recovery-code prompts. Credential bootstrap with the real pCloud
account, pCloud mount validation, and podcast target write tests have passed.
User-scoped systemd startup, saved-auth service restart, and credential
permission hardening have passed. Reboot recovery, external pCloud visibility,
repeatable health-check automation, and scheduled workload integration have
passed.

## Preconditions

- PiServ is reachable as `operator@piserv.example.com`.
- `operator` has sudo access.
- The pCloud account email is supplied by the operator during setup.
- The pCloud data region is European Union.
- The pCloud password is provided interactively during first login.
- If TOTP is enabled, use the patched CLI prompt documented below.
- No pCloud credentials are written into this repository.

## Target Shape

| Item | Decision |
| --- | --- |
| Backend | Official `pcloudcc` console client |
| Mount type | FUSE |
| Service manager | systemd user service |
| Runtime user | `operator` |
| pCloud account email | Operator-provided; do not store in docs |
| pCloud data region | European Union |
| Mount root | `/mnt/pcloud` |
| Podcast target | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |
| Podcast producer | `raiplaysound-cli-daily-sync` |
| Credential bootstrap | Manual first login with `pcloudcc -p -s -t` as `operator` |
| Required preflight | Mount present, writable, and round-trip file test passes |
| Account scope | Existing user pCloud account with full pCloud access |

## Client Installation

The `pcloudcc` client was built and installed live on PiServ on 2026-07-08.

Observed install facts:

| Item | Value |
| --- | --- |
| Source repository | `https://github.com/pcloudcom/console-client.git` |
| Source revision | `980d2cadf670f1b14642c7dbe015f95bd2306175` |
| Desired client version | `2.0.1` |
| Source path | `/opt/pcloudcc/console-client` |
| Installed binary | `/usr/local/bin/pcloudcc` |
| Installed library | `/usr/local/lib/libpcloudcc_lib.so` |
| Help/version line | `pCloud console client v.2.0.1` |
| TOTP options | `--trustdevice`, `--recoverycode` |
| Mount directory | `/mnt/pcloud`, owned by `operator` |

Use the Ansible reproduction path:

```sh
ansible-playbook ansible/playbooks/pcloudcc-install.yml
```

The role validates the installed client against `pcloudcc_version`, currently
`2.0.1`. The Git source pin is separate: `pcloudcc_repo_version` stores the
exact upstream revision used to build that client.

The role applies a Debian 13 `arm64` source patch because the official source
contains x86 `-mtune=core2` compiler tuning and legacy C constructs rejected by
current Debian GCC. The patch removes the x86 tuning flag, relaxes GCC 14 C
diagnostics that block the legacy code, and fixes several pointer/conversion
sites needed for a successful `arm64` build.

The role also applies a CLI TOTP prompt patch because the upstream sync library
contains two-factor APIs but the console-client wrapper did not expose TOTP or
recovery-code entry.

After manual credential bootstrap, the role can harden saved pCloud state and
manage the user-scoped mount service. It does not store credentials.

## Credential Bootstrap

The official `pcloudcc` client documents `-s` / `--savepassword` as the
password persistence mechanism. Source and live database inspection show that
successful saved login stores a reusable `auth` token and `saveauth` flag, then
removes the saved `pass` entry. It does not document a password config file or
password environment variable.

Run first login manually on PiServ as `operator`:

```sh
sudo install -d -o operator -g operator -m 0755 /mnt/pcloud
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -m /mnt/pcloud
```

`pcloudcc` prompts for the pCloud password and writes saved session state to
the local pCloud client database for the Unix user running the command. Do not
put the password in the command line, a systemd unit, an environment file,
Ansible variables, or this repository.

For a TOTP-enabled account, prefer marking PiServ trusted during first login:

```sh
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -t -m /mnt/pcloud
```

Use `-r` / `--recoverycode` only when entering a pCloud recovery code instead
of an authenticator-app TOTP.

### TOTP Support

Observed on PiServ on 2026-07-08:

| Check | Result |
| --- | --- |
| Command | `pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -m /mnt/pcloud` |
| Client output | `LOGIN_REQUIRED`, then `Unrecognized status` |
| Mount state | `/mnt/pcloud` was not mounted |
| Client log | pCloud API error `2297 Two factor authentication required` |

The installed `pcloudcc` binary was patched and rebuilt on PiServ on
2026-07-08. It now exposes:

| Option | Purpose |
| --- | --- |
| `-t`, `--trustdevice` | Ask pCloud to trust PiServ after successful two-factor login |
| `-r`, `--recoverycode` | Treat the entered two-factor value as a recovery code |

The patched TOTP login passed on PiServ on 2026-07-08. The foreground client
mounted `/mnt/pcloud` as FUSE source `pCloud.fs`, and the podcast target passed
a write/read/delete test.

The console can print numeric events during initial scan:

| Event | Meaning |
| --- | --- |
| `1073741824` | `PEVENT_USERINFO_CHANGED` |
| `1073741825` | `PEVENT_USEDQUOTA_CHANGED` |

These are expected user/account metadata events. The upstream console wrapper
prints them numerically because it only formats file, folder, and share events.

After any failed TOTP login, stop the foreground `pcloudcc` process and remove
`/tmp/psync_err.log`; the log can contain authentication-derived material.

After first login succeeds, non-interactive startup should pass only the
mount point:

```sh
pcloudcc -m /mnt/pcloud
```

The PiServ user service runs that command as `operator` with no account email,
password, TOTP, or recovery code in the unit.

EU-region login has been validated live. No explicit region setting was needed
for the source-built client.

## Credential Storage and Session Behavior

Observed on PiServ on 2026-07-08 after service hardening:

| Check | Result |
| --- | --- |
| State directory | `/home/operator/.pcloud`, mode `0700` |
| State files | `/home/operator/.pcloud/data.db*`, mode `0600` |
| Service command | `/usr/local/bin/pcloudcc -m /mnt/pcloud` |
| Stored DB keys | `auth`, `saveauth`, `username` |
| Missing DB key | `pass` |
| Linger | `Linger=yes` for `operator` |

The saved `auth` token is sensitive. It is protected by Unix ownership and
permissions, not by a desktop keychain or repository-managed encryption.

Service restart was validated by stopping `pcloudcc.service`, auditing the DB,
starting the service again, and confirming `/mnt/pcloud` remounted as
`pCloud.fs` without a password, email, or TOTP prompt.

Expected long-running behavior:

| Scenario | Expected Behavior | Operator Action |
| --- | --- | --- |
| Normal restart | Saved auth token is reused | None |
| TOTP still trusted | No TOTP prompt during service start | None |
| pCloud invalidates token or device | Client moves back to login-required state | Stop service and rerun manual login |
| Password or 2FA settings change | Saved auth may be revoked | Rerun manual `-p -s -t` login |

The session should be treated as persistent but not permanent. TOTP is only
needed when pCloud requires a fresh login. The service is intentionally
non-interactive; if pCloud rejects saved auth, the operator must run:

```sh
systemctl --user stop pcloudcc.service
pcloudcc -u "PCLOUD_ACCOUNT_EMAIL" -p -s -t -m /mnt/pcloud
systemctl --user start pcloudcc.service
```

## Validation Plan

1. Install build prerequisites on PiServ.
2. Build `pcloudcc` from the official pCloud console-client source.
3. Run the patched TOTP bootstrap path for the current account. Done.
4. Run the manual first login with `-p -s` as `operator`. Done.
5. Start `pcloudcc` manually with `/mnt/pcloud` as the mount point. Done.
6. Confirm the mount appears in `findmnt`. Done.
7. Confirm `My Music/Podcasts/raiplaypodcast` exists under the mount. Done.
8. Write, read, and delete a small test file through the podcast target. Done.
9. Confirm the file appears in pCloud from another client. Done.
10. Wrap the mount in systemd without passing the pCloud password. Done.
11. Reboot PiServ and confirm the mount recovers without manual shell state.
    Done.
12. Run `raiplaysound-cli-daily-sync` with health-check gating. Done.

## Health Checks

Use the project wrapper from the repository root:

```sh
scripts/check-pcloudcc-health.sh
```

Or run the Ansible health-check entry point:

```sh
ansible-playbook ansible/playbooks/pcloudcc-health-check.yml
```

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

- Keep password bootstrap manual; automate only non-secret service settings.

# Hermes Agent

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Planned Inference Routing](#planned-inference-routing)
- [Deploy](#deploy)
- [Complete ChatGPT Login](#complete-chatgpt-login)
- [Open the Private Dashboard](#open-the-private-dashboard)
- [Validate](#validate)
- [Backup and Restore](#backup-and-restore)
- [Recovery](#recovery)

## Purpose

Operate the PiServ-resident Nous Hermes Agent with Codex authenticated through
the operator's ChatGPT subscription. Hermes owns persistent memory, skills,
sessions, and audit data; Codex is the initial inference provider.

## Current State

Live state observed on 2026-07-30:

| Item | State |
| --- | --- |
| Hermes | `0.19.0`, upstream commit `240afd0b70a016ba17568d597e0f2c32f94f4cfd` |
| Runtime identity | `hermes-agent`, system account with no login shell |
| Persistent data | `/var/lib/hermes-agent`, mode `0700` |
| Codex CLI | `0.145.0`, official ARM64 archive with SHA-256 verification |
| Provider | `openai-codex`, awaiting operator device login |
| Enabled toolsets | `memory`, `skills` |
| Write gates | Memory and skill writes require approval |
| Disabled toolsets | Terminal, file, browser, code execution, Home Assistant, and all other bundled toolsets |
| Dashboard | `127.0.0.1:9119`, reachable only locally or through an SSH tunnel |
| Backups | Daily full archive on `/mnt/external-data/backups/hermes-agent` |

The first live dashboard probe returned HTTP `200`. The first backup contained
2,749 files, compressed 218.6 MB to 72.3 MB, and completed in 11 seconds.
After the Ansible convergence restart, the idle dashboard process used about
135 MiB RSS; the host retained about 2.7 GiB available memory.
A forced process failure restarted automatically and returned HTTP `200` with a
new PID after 13 seconds.

The pinned upstream revision contains a tracked, process-specific
`.lazy-refresh-incomplete` marker. The role removes it after installation so
the unprivileged runtime does not attempt package repair on every command.

## Planned Inference Routing

Codex is an operator-pre-authorized inference provider. When route selection
and non-text handling are enabled, Hermes may send an eligible request or
attachment to Codex without a per-request confirmation. Each response must
include a compact provider-provenance note when Codex analyzed its context;
the note must not block text, audio, or structured results.

The corresponding audit record must contain the provider, route reason, data
classification, timestamp, request ID, and outcome without persisting request
or response contents. Provider routing does not authorize a write operation or
enable any currently disabled toolset.

The current deployment has no automatic route selection and keeps the vision
toolset disabled. This is a planned policy, not an active routing feature.

## Deploy

The external SSD must be mounted and the `external-data` group must exist:

```sh
findmnt /mnt/external-data
getent group external-data
```

Apply the dedicated playbook:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

The full installation entry point imports this playbook after external storage
and the Home Assistant MQTT Agent.

## Complete ChatGPT Login

Run the prepared operator helper:

```sh
scripts/hermes-chatgpt-login.sh
```

Open the displayed URL, enter the device code, and authorize the ChatGPT Pro
account. The helper then imports that session into Hermes, restarts the
dashboard, and prints the Codex, Hermes, and tool-policy states.

The underlying first login command is:

```sh
ssh -t admin@PiServ.local \
  'sudo -u hermes-agent -H env \
  CODEX_HOME=/var/lib/hermes-agent/codex \
  codex login --device-auth'
```

Hermes creates its own refresh session after the import so routine Codex CLI
use does not rotate the token underneath Hermes.

## Open the Private Dashboard

Create an SSH tunnel from the operator Mac:

```sh
ssh -N -L 9119:127.0.0.1:9119 admin@PiServ.local
```

Open `http://127.0.0.1:9119`. Keep the dashboard loopback-only until an
authenticated LAN or Tailnet exposure policy is implemented.

## Validate

Verify service, provider, tool policy, and both runtimes:

```sh
ssh admin@PiServ.local '
  sudo systemctl --no-pager status hermes-agent-dashboard.service
  curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9119/
  sudo -u hermes-agent -H env \
    HERMES_HOME=/var/lib/hermes-agent \
    CODEX_HOME=/var/lib/hermes-agent/codex \
    hermes auth status openai-codex
  sudo -u hermes-agent -H env \
    HERMES_HOME=/var/lib/hermes-agent \
    hermes tools list --platform cli
  sudo -u hermes-agent -H env \
    CODEX_HOME=/var/lib/hermes-agent/codex \
    codex login status
'
```

Expected results after login:

- Dashboard service is active and HTTP returns `200`.
- Hermes and Codex report authenticated ChatGPT sessions.
- Only `memory` and `skills` are enabled.
- `terminal`, `file`, `browser`, `code_execution`, and `homeassistant` remain
  disabled.

Complete the first inference test in the dashboard. Do not enable additional
tools as part of the login test.

## Backup and Restore

Run an on-demand full backup:

```sh
ssh admin@PiServ.local \
  'sudo systemctl start hermes-agent-backup.service'
```

Inspect the timer and archives:

```sh
ssh admin@PiServ.local '
  sudo systemctl list-timers hermes-agent-backup.timer --no-pager
  sudo find /mnt/external-data/backups/hermes-agent \
    -maxdepth 1 -type f -name "hermes-backup-*.zip" -printf "%f %s bytes\n"
'
```

Archives include credentials and therefore remain owned by `hermes-agent` in a
`0700` directory. The timer retains 30 days.

Test restore only into a separate temporary Hermes home until the persistence
gate is complete. Never overwrite the live home without a fresh backup and an
explicit maintenance window.

## Recovery

Inspect service logs:

```sh
ssh admin@PiServ.local \
  'sudo journalctl -u hermes-agent-dashboard.service -n 100 --no-pager'
```

Reapply configuration without changing credentials:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

The role does not manage `auth.json`, `.env` secrets, memory, skills, sessions,
or backup contents. Reapplication preserves those runtime-owned files.

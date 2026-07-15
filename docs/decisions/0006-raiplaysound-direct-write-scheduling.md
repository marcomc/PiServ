# 0006: RaiPlaySound Direct-Write Scheduling

## Status

Accepted on 2026-07-08.

## Context

PiServ now has a validated `pcloudcc` FUSE mount at `/mnt/pcloud` and a
repeatable health check for the podcast target. The scheduled
`raiplaysound-cli` workload needs generated media, feeds, and the landing index
to appear in the pCloud-backed podcast folder consumed by the podcast proxy.

Earlier fallback planning kept local NVMe staging available if direct pCloud
writes were unreliable.

## Decision

Run `raiplaysound-cli-daily-sync` as a user-scoped systemd oneshot service for
`admin`, triggered by a user-scoped systemd timer.

Use direct writes to:

```text
/mnt/pcloud/My Music/Podcasts/raiplaypodcast
```

Gate every scheduled run with the pCloud health check before the CLI writes any
podcast output.

Use Ansible to install the CLI from the pinned upstream source revision, create
the non-secret PiServ config from role defaults when missing, and manage:

| Unit | Purpose |
| --- | --- |
| `raiplaysound-cli-daily-sync.service` | Run one favourites sync |
| `raiplaysound-cli-daily-sync.timer` | Trigger the service daily |

The timer runs at 08:00 local time with a short randomized delay.

## Consequences

- Podcast output lands directly in the pCloud-backed target without a local
  staging copy step.
- pCloud mount health is now a hard prerequisite for the scheduled workload.
- A degraded pCloud mount blocks the job before downloads start.
- Direct writes keep the pipeline simple, but long media downloads and `ffmpeg`
  conversions exercise the FUSE mount directly.
- NVMe staging remains the fallback if direct-write reliability degrades.
- Direct edits to the PiServ config are preserved by later playbook runs because
  the playbook uses create-only config mode.
- The PiServ playbook supplies non-secret create-only defaults for the podcast
  target, RSS base URL, and local email summary wiring. Existing live config
  edits are preserved by later playbook runs.

## Validation

Validated on PiServ on 2026-07-08:

| Check | Result |
| --- | --- |
| CLI version | `raiplaysound-cli 2.5.0` |
| Source revision | `55dfb29c0c15cc30c603338072261fabf5e52fe4` |
| Timer state | active and waiting |
| Manual service run | exited with status `0/SUCCESS` |
| pCloud preflight | `pcloudcc_health=ok` |
| Favourites run | `done=10`, `errors=0` |
| Direct-write proof | One new `seigradi` `.m4a` written under the pCloud target |

The manual run completed from 12:28:19 to 12:32:37 CEST.

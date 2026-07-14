# 0012: PiServ User-Account Policy

## Status

Accepted and implemented on 2026-07-14.

## Context

The live PiServ host has one human login account, `admin`, with passwordless
sudo through the `sudo` group. Root SSH login is disabled and no `operator`
account exists. The current pCloud, RaiPlaySound, Freenove, and touchscreen
services use the `admin` user because they depend on its saved pCloud state or
the active local desktop session.

## Decision

| Area | Decision |
| --- | --- |
| Human administration | Keep `admin` as the only human sudo account for now |
| SSH | Keep key-based SSH for `admin`; keep root SSH login disabled |
| Current user-scoped workloads | Run under `admin` until a workload can be isolated without losing the required desktop or pCloud session |
| Future daemons | Add a dedicated non-login service account only when file ownership or privilege isolation requires it |
| Account lifecycle | Do not create or delete users as part of the baseline role |
| Reproduction source | Store the connection account as `ansible_user` in project inventory |

The project inventory sets `ansible_user=admin`. The current PiServ playbooks
pass that value explicitly to the reusable roles' user variables. There are no
additional PiServ-wide account aliases. The policy does not silently migrate
or remove accounts on a recovery image.

## Consequences

- pCloud credentials and the user-scoped pCloud mount remain in `/home/admin`.
- Freenove launchers and the touchscreen idle service remain in the `admin`
  desktop session.
- A future service account will need its own ownership, systemd, and secret
  handling decision before it is introduced.

## Validation

Live checks on `PiServ.local` confirmed:

```text
admin exists with UID 1000
admin is a member of sudo
root and admin are the only accounts with interactive shells
operator does not exist
sudo -n true succeeds for admin
```

The inventory uses `ansible_user=admin`, and the reusable roles retain explicit
user variables as override points for deployments that intentionally use a
different account.

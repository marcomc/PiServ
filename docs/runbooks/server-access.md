# Server Access Runbook

## Purpose

Verify that this host can reach PiServ through SSH and that the `admin` user
can perform sudo operations.

## Preconditions

- PiServ is powered on.
- The server is connected to Wi-Fi.
- SSH key access from this host has been exchanged.
- The `admin` account exists on PiServ.

## Commands

Verify mDNS access:

```sh
ssh admin@PiServ.local 'hostname && id && sudo -n true && echo sudo-ok'
```

Verify direct IP access:

```sh
PISERV_IP=$(getent ahostsv4 PiServ.local | awk 'NR == 1 { print $1 }')
ssh "admin@${PISERV_IP}" 'hostname && id && sudo -n true && echo sudo-ok'
```

## Expected Result

- `hostname` returns the PiServ hostname.
- `id` returns the `admin` user identity.
- `sudo-ok` prints without an interactive password prompt.

## Observed Results

| Date | Target | Result |
| --- | --- | --- |
| 2026-07-02 | `admin@PiServ.local` | Returned `PiServ`, `admin`, and `sudo-ok` |

## Follow-Up

- If mDNS fails but the IP works, document name-resolution state before changing
  host or network configuration.
- If sudo requires a password, document that behavior before deciding whether
  automation should use passwordless sudo or explicit become prompting.
- Add these checks to automation once the baseline Ansible layout exists.

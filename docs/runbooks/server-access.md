# Server Access Runbook

## Purpose

Verify that this host can reach PiServ through SSH and that the `operator` user
can perform sudo operations.

## Preconditions

- PiServ is powered on.
- The server is connected to Wi-Fi.
- SSH key access from this host has been exchanged.
- The `operator` account exists on PiServ.

## Commands

Verify mDNS access:

```sh
ssh operator@piserv.example.com 'hostname && id && sudo -n true && echo sudo-ok'
```

Verify direct IP access:

```sh
ssh operator@192.0.2.181 'hostname && id && sudo -n true && echo sudo-ok'
```

## Expected Result

- `hostname` returns the PiServ hostname.
- `id` returns the `operator` user identity.
- `sudo-ok` prints without an interactive password prompt.

## Observed Results

| Date | Target | Result |
| --- | --- | --- |
| 2026-07-02 | `operator@piserv.example.com` | Returned `PiServ`, `operator`, and `sudo-ok` |

## Follow-Up

- If mDNS fails but the IP works, document name-resolution state before changing
  host or network configuration.
- If sudo requires a password, document that behavior before deciding whether
  automation should use passwordless sudo or explicit become prompting.
- Add these checks to automation once the baseline Ansible layout exists.

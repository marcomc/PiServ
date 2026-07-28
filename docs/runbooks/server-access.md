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
dscacheutil -q host -a name PiServ.local
dns-sd -Q PiServ.local A
ssh admin@PiServ.local 'hostname && id && sudo -n true && echo sudo-ok'
```

Verify direct IP access with the current DHCP lease (from the router or local
console):

```sh
PISERV_IP=<current-DHCP-lease>
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
  host or network configuration. Check PiServ's kernel log for a blocked
  unicast UDP/5353 query from the client and verify that the managed UFW policy
  allows UDP `5353` from the LAN CIDR without restricting the destination to
  `224.0.0.251`.
- Use the current direct IPv4 address as the Ansible fallback while repairing
  mDNS: `ansible-playbook ... -e "ansible_host=${PISERV_IP}"`.
- If sudo requires a password, document that behavior before deciding whether
  automation should use passwordless sudo or explicit become prompting.
- Add these checks to automation once the baseline Ansible layout exists.

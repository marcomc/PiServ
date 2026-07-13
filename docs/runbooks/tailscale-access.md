# Tailscale Access

## Table of Contents

- [Purpose](#purpose)
- [Preconditions](#preconditions)
- [Install](#install)
- [First Login](#first-login)
- [Client Access](#client-access)
- [HA Subnet Router](#ha-subnet-router)
- [Verify](#verify)
- [Operate](#operate)
- [Debug](#debug)
- [LAN Reply Routing](#lan-reply-routing)
- [Recovery](#recovery)
- [Observed PiServ State](#observed-piserv-state)
- [Automation Follow-Up](#automation-follow-up)

## Purpose

Install Tailscale on PiServ, join it to the tailnet, and validate standard
OpenSSH, firewall integration, and high-availability subnet routing.

## Preconditions

| Check | Command |
| --- | --- |
| SSH works | `ssh operator@piserv.example.com true` |
| Sudo works | `ssh operator@piserv.example.com 'sudo -n true'` |
| OS codename | `ssh operator@piserv.example.com '. /etc/os-release; echo "$VERSION_CODENAME"'` |

Expected PiServ OS codename: `trixie`.

## Install

Run the Ansible playbook:

```sh
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbooks/tailscale.yml
```

Expected result:

- the pinned `artis3n.tailscale` Galaxy collection is installed
- the `tailscale` package is installed
- `tailscaled` is enabled and active

## First Login

Use manual login for PiServ unless a private one-off auth key is intentionally
supplied at runtime:

```sh
ssh operator@piserv.example.com
sudo tailscale up --hostname=piserv
```

Open the printed login URL, approve PiServ, and wait for the command to finish.

Do not enable Tailscale SSH during this step. Standard OpenSSH remains the
administration path.

For a recovery build where browser login is inconvenient, use a private one-off
auth key from the Tailscale operator console:

```sh
(
  set -eu
  tailscale_vars=$(mktemp)
  trap 'rm -f "$tailscale_vars"' EXIT HUP INT TERM
  chmod 600 "$tailscale_vars"

  python3 - "$tailscale_vars" <<'PY'
import getpass
import json
import pathlib
import sys

variables = {
    "tailscale_authkey": getpass.getpass("Tailscale auth key: "),
    "tailscale_up_skip": False,
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(variables), encoding="utf-8")
PY

  ansible-playbook ansible/playbooks/tailscale.yml \
    -e "@$tailscale_vars"
)
```

The subshell removes the protected temporary variables file on exit. Do not
store auth keys in Git, shell history, persistent files, runbooks, or project
variables.

## Client Access

There are two separate access steps:

| Step | Owner | Purpose |
| --- | --- | --- |
| Join PiServ to the tailnet | PiServ operator | Gives PiServ a Tailscale IP and optional MagicDNS name |
| Join a client device to the tailnet | User or tailnet operator | Lets that device route to PiServ over Tailscale |

After PiServ first login is approved, get the PiServ Tailscale address:

```sh
ssh operator@piserv.example.com 'tailscale ip -4'
```

For an existing trusted tailnet user:

1. Install Tailscale on the client device.
2. Sign in to the same tailnet.
3. Confirm the client shows as connected.
4. Connect to PiServ with standard OpenSSH:

   ```sh
   ssh operator@PISERV_TAILSCALE_IP
   ```

If MagicDNS is enabled in the Tailscale operator console, the client can use the
machine name instead of the `100.x.y.z` address:

```sh
ssh operator@piserv
```

For a new user, do not share account credentials. Use one of these Tailscale
operator-console paths:

| Need | Admin-console action |
| --- | --- |
| User should join the same tailnet | Users page, send a welcome email or invite link |
| User should access only PiServ from another tailnet | Machines page, share the PiServ machine |

Tailscale provides the network path only. Linux account access is still enforced
by PiServ. A user needs an allowed Linux username and SSH key on PiServ before
`ssh` will succeed.

## HA Subnet Router

PiServ advertises its local IPv4 LAN as one member of a high-availability
subnet-router group. It enables IPv4 forwarding and default Tailscale SNAT, but
rejects imported routes so directly connected LAN traffic remains local.

See [Tailscale HA subnet routing](tailscale-ha-subnet-routing.md) for route
approval, verification, controlled failover, and recovery.

## Verify

Run on PiServ:

```sh
systemctl is-enabled tailscaled
systemctl is-active tailscaled
tailscale version
tailscale status
tailscale ip -4
ip addr show tailscale0
sudo tailscale debug prefs
```

Run from a Tailscale-connected client:

```sh
ssh operator@PISERV_TAILSCALE_IP
```

Expected result:

- `tailscaled` is enabled and active
- `tailscale status` shows PiServ connected
- `tailscale ip -4` returns a `100.x.y.z` address
- `RouteAll` is `false` in `tailscale debug prefs`
- `NoSNAT` is `false` in `tailscale debug prefs`
- `net.ipv4.ip_forward` is `1`
- SSH over the Tailscale IP reaches the same PiServ host

## Operate

| Task | Command / Location |
| --- | --- |
| Show status | `tailscale status` |
| Show IPs | `tailscale ip` |
| Re-authenticate | Follow [Recovery](#recovery) and preserve every non-default `tailscale up` flag |
| Disconnect temporarily | `sudo tailscale down` |
| Remove tailnet login | `sudo tailscale logout` |
| Review key expiry | Tailscale operator console, Machines page |

For a trusted always-on server, consider disabling key expiry in the Tailscale
operator console after login. Keep expiry enabled when physical control of the
device or tailnet membership is uncertain.

## Debug

Collect local diagnostics:

```sh
sudo journalctl -u tailscaled -n 200 --no-pager
tailscale status --json
tailscale netcheck
ip route
ip addr show tailscale0
```

Check package source state:

```sh
cat /etc/apt/sources.list.d/tailscale.sources
ls -l /etc/apt/keyrings/tailscale.gpg
apt-cache policy tailscale
```

## LAN Reply Routing

When direct LAN ICMP or SSH fails while Tailscale access works, check whether
PiServ is accepting an overlapping advertised subnet route:

```sh
sudo tailscale debug prefs
ip route get CLIENT_LAN_IP from PISERV_LAN_IP
```

Expected result: `RouteAll` is `false` and the route uses the physical LAN
interface. On 2026-07-13, `RouteAll: true` selected `tailscale0` for a local
client. PiServ received TCP SYN packets but the client never received its
SYN-ACK. Running the Tailscale playbook, or the recovery command below,
restored direct LAN ICMP and SSH.

## Recovery

Reinstall package state:

```sh
ansible-playbook ansible/playbooks/tailscale.yml
```

The [official `tailscale up` reference](https://tailscale.com/docs/reference/tailscale-cli/up)
states that flags are not persisted between runs. Force a fresh login while
repeating every current non-default flag.

For PiServ's HA subnet-router policy:

```sh
sudo tailscale up --force-reauth --hostname=piserv \\
  --advertise-routes=LAN_IPV4_CIDR --accept-routes=false \\
  --snat-subnet-routes=true
```

Include any other non-default `tailscale up` flags that PiServ uses. Reapply the
Tailscale playbook after recovery to restore forwarding and exact route policy.
Do not use `--reset` unless the intent is to clear routes and other settings.

If the tailnet record is wrong or stale, remove PiServ from the Tailscale operator
console and run first login again.

## Observed PiServ State

| Item | Observed value |
| --- | --- |
| OS codename | `trixie` |
| Architecture | `arm64` |
| Ansible collection | `artis3n.tailscale` `1.2.1` |
| Tailscale package version | `1.98.8` |
| `tailscaled` state | `enabled`, `active` |
| Tailscale IPv4 | `PISERV_TAILSCALE_IP` |
| Tailscale backend state | `Running` |
| Accept advertised routes | `false` |
| Source NAT for subnet routes | Enabled |
| IPv4 forwarding | Enabled |
| Login method | Manual browser login |

Live installation validation:

```text
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbooks/tailscale.yml
ansible-playbook ansible/playbooks/tailscale.yml
second run: changed=0
tailscale status backend: NeedsLogin
```

Latest connection and firewall verification on 2026-07-13:

```text
tailscale IPv4: PISERV_TAILSCALE_IP
tailscale backend: Running
IPv4 forwarding: enabled
accept advertised routes: false
subnet-route source NAT: enabled
UFW tailscale0 ingress: allowed
UFW Tailscale-to-LAN route: allowed
advertised route activation: pending Tailscale admin-console approval
new LAN and Tailscale OpenSSH connections: passed
```

## Automation Follow-Up

- Keep `ansible/playbooks/tailscale.yml` as the installation path.
- Keep auth keys out of repository files.
- Keep route approval, grants, and failover validation under the HA subnet
  routing runbook.
- Keep `ansible/playbooks/firewall.yml` as the host firewall reproduction path.

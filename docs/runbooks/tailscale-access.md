# Tailscale Access

## Table of Contents

- [Purpose](#purpose)
- [Preconditions](#preconditions)
- [Install](#install)
- [First Login](#first-login)
- [Client Access](#client-access)
- [Optional Subnet Router](#optional-subnet-router)
- [Verify](#verify)
- [Operate](#operate)
- [Debug](#debug)
- [Recovery](#recovery)
- [Observed PiServ State](#observed-piserv-state)
- [Automation Follow-Up](#automation-follow-up)

## Purpose

Install Tailscale on PiServ, join it to the tailnet, and validate remote access
before finalizing firewall rules.

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

## Optional Subnet Router

Enable this only when tailnet devices must reach LAN-only devices through
PiServ. It is not an exit node and does not route general internet traffic.

PiServ is connected to the `192.0.2.0/24` LAN. Before advertising that
subnet, confirm that PiServ has completed first login:

```sh
tailscale status
tailscale ip -4
```

Enable persistent IPv4 forwarding:

```sh
printf '%s\n' 'net.ipv4.ip_forward = 1' \
  | sudo tee /etc/sysctl.d/99-piserv-tailscale-router.conf >/dev/null
sudo sysctl --system
```

If PiServ will later advertise an IPv6 subnet, enable IPv6 forwarding too:

```sh
printf '%s\n' 'net.ipv6.conf.all.forwarding = 1' \
  | sudo tee -a /etc/sysctl.d/99-piserv-tailscale-router.conf >/dev/null
sudo sysctl --system
```

Advertise the complete set of desired IPv4 routes. This command replaces the
advertised-route list, so retain existing routes when adding another subnet:

```sh
sudo tailscale set --advertise-routes=192.0.2.0/24
```

Approve the proposed route in the Tailscale operator console:

1. Open `Machines`, then select PiServ.
2. Open `Subnets`, select `Edit`, approve `192.0.2.0/24`, and save.
3. Confirm the tailnet policy allows the intended users or devices to reach
   `192.0.2.0/24`.

Route approval and tailnet access policy are independent. Leave subnet-route
SNAT enabled, which is Tailscale's default, so LAN-only devices return traffic
through PiServ without home-router changes.

macOS, Windows, iOS, Android, and tvOS clients accept approved routes
automatically. On a Linux client, opt in explicitly:

```sh
sudo tailscale set --accept-routes
```

Verify from a Tailscale-connected client using a LAN-only device IP, not
PiServ's own LAN address:

```sh
ping 192.0.2.LAN_DEVICE
```

Do not advertise `192.0.2.0/24` for clients that are themselves connected to
another `192.0.2.0/24` LAN. The overlapping local route will take precedence.

## Verify

Run on PiServ:

```sh
systemctl is-enabled tailscaled
systemctl is-active tailscaled
tailscale version
tailscale status
tailscale ip -4
ip addr show tailscale0
```

Run from a Tailscale-connected client:

```sh
ssh operator@PISERV_TAILSCALE_IP
```

Expected result:

- `tailscaled` is enabled and active
- `tailscale status` shows PiServ connected
- `tailscale ip -4` returns a `100.x.y.z` address
- SSH over the Tailscale IP reaches the same PiServ host

## Operate

| Task | Command / Location |
| --- | --- |
| Show status | `tailscale status` |
| Show IPs | `tailscale ip` |
| Re-authenticate | `sudo tailscale up --force-reauth --hostname=piserv` |
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

## Recovery

Reinstall package state:

```sh
ansible-playbook ansible/playbooks/tailscale.yml
```

Force a fresh login:

```sh
sudo tailscale up --force-reauth --hostname=piserv
```

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
| Tailscale IPv4 | `100.64.0.10` |
| Tailscale backend state | `Running` |
| Advertised routes | None |
| Login method | Manual browser login |

Live installation validation:

```text
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook ansible/playbooks/tailscale.yml
ansible-playbook ansible/playbooks/tailscale.yml
second run: changed=0
tailscale status backend: NeedsLogin
```

Latest connection verification on 2026-07-10:

```text
tailscale IPv4: 100.64.0.10
tailscale backend: Running
IPv4 forwarding: disabled
advertised routes: none
```

## Automation Follow-Up

- Keep `ansible/playbooks/tailscale.yml` as the installation path.
- Keep auth keys out of repository files.
- Keep subnet routing separate from the installation playbook. If enabled,
  codify forwarding and `tailscale set --advertise-routes` in a dedicated
  PiServ-owned routing role or playbook.
- Finalize firewall policy after LAN and Tailscale access are both verified.

# Cockpit Web Console

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [Access](#access)
- [Validation](#validation)
- [Recovery](#recovery)

## Purpose

Operate PiServ's Cockpit HTTPS administration console for system-resource
inspection and supported host administration.

## Apply

Apply the base role and firewall policy:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
ansible-playbook ansible/playbooks/firewall.yml
```

The base role installs Debian's `cockpit`, `cockpit-storaged`,
`cockpit-sosreport`, and `cockpit-packagekit` packages. It enables
`cockpit.socket`, which activates the HTTPS service on demand.

Cockpit Storage is an operator inspection and emergency-management surface;
Ansible remains the source of truth for PiServ partitions, mounts, and ACLs.
For the managed external SSD, reapply
[`external-storage.yml`](../../ansible/playbooks/external-storage.yml) after
any inspection or emergency action, and do not repartition or reformat that
disk through Cockpit.
PackageKit is available for interactive package inspection, but normal updates
remain Ansible- and unattended-upgrades-controlled.

## Access

Open the console from the IPv4 LAN:

```text
https://PiServ.local:9090
```

The initial certificate is self-signed. Verify the certificate identifies
PiServ before accepting the browser warning. Log in as `admin` with the
existing local PAM password. SSH password authentication remains disabled and
does not disable Cockpit's PAM login.

UFW allows TCP `9090` only from the current IPv4 LAN. The existing
`tailscale0` ingress rule also permits authenticated tailnet access, subject to
tailnet grants and ACLs. IPv6 LAN ingress remains denied.

## Validation

The 2026-07-27 deployment confirmed Debian Cockpit `337-1+deb13u1`, the three
selected extension packages, an enabled and active `cockpit.socket`, and an
HTTPS login page on port `9090`.

Run on PiServ:

```sh
sudo systemctl is-enabled cockpit.socket
sudo systemctl is-active cockpit.socket
curl -kfsS https://127.0.0.1:9090/ | grep -F cockpit/static/login.js
sudo ss -ltnp '( sport = :9090 )'
dpkg -l cockpit cockpit-storaged cockpit-sosreport cockpit-packagekit
cockpit-bridge --packages | grep -E 'storage|sosreport|packagekit'
```

Run from a LAN client:

```sh
curl -kfsS -o /dev/null -w '%{http_code}\n' https://PiServ.local:9090/
```

The expected HTTP status is `200`. The base role repeats the local HTTPS
response assertion during every normal playbook run. Browser authentication is
not automated because it requires the local account password.

## Recovery

Inspect the socket and service:

```sh
ssh admin@PiServ.local 'sudo systemctl status cockpit.socket cockpit.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u cockpit.socket -u cockpit.service -n 100 --no-pager'
```

Reapply the base playbook to restore the package and socket. Reapply the
firewall playbook if the LAN port is blocked. Do not expose TCP `9090` beyond
the LAN or Tailscale without a reviewed authentication and firewall change.

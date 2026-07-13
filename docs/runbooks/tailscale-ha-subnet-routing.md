# Tailscale HA Subnet Routing

## Table of Contents

- [Purpose](#purpose)
- [Policy](#policy)
- [Apply](#apply)
- [Approve Route](#approve-route)
- [Verify](#verify)
- [Failover Test](#failover-test)
- [Recovery](#recovery)
- [Observed PiServ State](#observed-piserv-state)

## Purpose

Operate PiServ as one member of a Tailscale high-availability subnet-router
group for the local IPv4 LAN. This permits remote tailnet clients to reach
non-Tailscale LAN devices by their normal IPv4 addresses.

## Policy

PiServ advertises the current IPv4 prefix of its default route. Every router in
the HA group must advertise the exact same prefix. PiServ enables IPv4
forwarding, keeps Tailscale source NAT enabled, and rejects imported subnet
routes.

The Tailscale control plane chooses the active router and fails over to another
member when the active router becomes unavailable. PiServ does not manage route
approval, tailnet grants, or peer-router configuration.

## Apply

Install pinned dependencies and apply both policies:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
ansible-playbook ansible/playbooks/tailscale.yml
ansible-playbook ansible/playbooks/firewall.yml
```

Expected result:

- `net.ipv4.ip_forward` is `1`.
- PiServ advertises the IPv4 prefix of its current default route.
- `RouteAll` is `false` and `NoSNAT` is `false`.
- UFW permits forwarded traffic from `tailscale0` only to the local IPv4 LAN.

## Approve Route

The route advertisement is inert until approved in the Tailscale admin console:

1. Open `Machines` and select PiServ.
2. Open `Subnets` or select `Review subnet routes`.
3. Enable the advertised local IPv4 route.
4. Confirm tailnet grants allow the intended users to reach that subnet.

Do not use PiServ as an exit node for this purpose.

## Verify

Run on PiServ:

```sh
sudo sysctl -n net.ipv4.ip_forward
sudo tailscale debug prefs
sudo ufw status verbose
```

From a remote Tailscale-connected macOS or iOS client, access a non-Tailscale
LAN device by its local IPv4 address:

```sh
ping LAN_DEVICE_IPV4
nc -vz LAN_DEVICE_IPV4 PORT
```

Expected result: the client reaches the LAN device without an installed
Tailscale client. macOS and iOS accept approved subnet routes automatically.

## Failover Test

Schedule this test because it temporarily withdraws the active router:

1. Verify remote access to a non-Tailscale LAN device.
2. Take the current active router down with `sudo tailscale down`.
3. Wait at least 20 seconds, then repeat the remote access test.
4. Restore the router with `sudo tailscale up` using its documented settings.
5. Confirm access remains available and record which router handled traffic.

Use exact matching prefixes on every router. A broader prefix is not a failover
candidate for a more-specific prefix.

## Recovery

If PiServ has accepted peer subnet routes and direct LAN access fails:

```sh
sudo tailscale set --accept-routes=false
ansible-playbook ansible/playbooks/tailscale.yml
```

If PiServ no longer advertises the local LAN, reapply the Tailscale playbook.
Do not manually add broad UFW forwarding rules; restore the managed firewall
policy instead.

## Observed PiServ State

Before the HA policy was applied on 2026-07-13:

```text
IPv4 forwarding: disabled
accept advertised routes: false
advertised local IPv4 route: configured but not active
```

After live application on 2026-07-13:

```text
IPv4 forwarding: enabled
accept advertised routes: false
subnet-route source NAT: enabled
UFW Tailscale-to-LAN route: active
LAN and Tailscale administration: passed
advertised route activation: pending Tailscale admin-console approval
```

Follow-up action: approve PiServ's advertised route and perform the controlled
failover test from a remote tailnet client.

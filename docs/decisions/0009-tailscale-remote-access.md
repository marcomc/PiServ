# 0009: Tailscale Remote Access

## Status

Accepted and implemented for package installation, manual tailnet login, and
firewall integration. High-availability subnet-router policy is defined by
decision 0011.

## Context

PiServ must remain reachable from the local LAN and from devices connected over
Tailscale. Tailscale must be connected before the restrictive host firewall is
enabled so a second administration path can be verified.

Tailscale's official Linux documentation supports Raspberry Pi OS and Debian
systems. The official package index currently lists Debian Trixie as stable and
publishes codename-specific apt keyring and source-list files.

## Decision

PiServ will install Tailscale through the upstream `artis3n.tailscale.machine`
Ansible Galaxy collection role. The dependency is pinned in
`ansible/requirements.yml`.

Initial authentication will be manual:

```sh
sudo tailscale up --hostname=piserv
```

No Tailscale auth key will be stored in this repository. Non-interactive login
can be done by overriding the collection role's `tailscale_up_skip` default and
supplying `tailscale_authkey` at runtime through private Ansible input.

Tailscale SSH is not enabled for now. PiServ keeps standard OpenSSH as the
administration entry point.

The host firewall permits ingress through `tailscale0` and leaves Tailscale in
its default netfilter mode. See decision 0010 for the UFW policy boundary.

PiServ must not accept advertised subnet routes. The Tailscale playbook enforces
`tailscale set --accept-routes=false`. Accepting the local LAN prefix would
route PiServ's replies through `tailscale0` instead of its physical LAN
interface, preventing direct LAN connections from completing.

## Consequences

- Tailscale package installation and `tailscaled` service state are delegated to
  a maintained upstream role and have been validated on PiServ.
- The project now depends on installing pinned Ansible collection requirements
  before running the Tailscale playbook.
- Tailnet membership still requires either a one-time manual browser login or a
  private runtime auth key.
- Device key expiry should be reviewed in the Tailscale operator console after
  login. Disabling key expiry improves server continuity but increases exposure
  if the device or node key is compromised.
- PiServ subnet-router policy, including forwarding, route advertisement, SNAT,
  and UFW forwarding rules, is defined by decision 0011.
- Tailnet grants and ACLs govern which tailnet identities may use the accepted
  `tailscale0` ingress path.

## Validation

Validated installation:

```sh
ansible-playbook ansible/playbooks/tailscale.yml
ansible-playbook ansible/playbooks/tailscale.yml
ssh admin@PiServ.local 'tailscale version; systemctl is-active tailscaled'
```

Observed result:

```text
artis3n.tailscale 1.2.1 installed from ansible/requirements.yml
Tailscale 1.98.8 installed
tailscaled active
second Ansible run changed=0
```

Tailnet login validation:

```sh
ssh admin@PiServ.local 'tailscale status && tailscale ip -4'
```

Observed result: PiServ is connected with an assigned Tailscale IPv4 address.
New standard OpenSSH and VNC connections over Tailscale passed after UFW was
enabled. On 2026-07-13, accepting an overlapping LAN route made direct LAN SSH
and ICMP fail. Disabling route acceptance restored both paths. PiServ now keeps
route acceptance disabled while advertising its own local IPv4 LAN for HA.

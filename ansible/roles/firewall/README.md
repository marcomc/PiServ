# Ansible Role: Firewall

Install and configure UFW with explicit default policies, serial rule
application, logging, service state, and runtime validation.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Rule Definitions](#rule-definitions)
- [Example Playbook](#example-playbook)
- [Supported Platforms](#supported-platforms)
- [Behavior](#behavior)
- [Tailscale Integration](#tailscale-integration)
- [Validation](#validation)
- [Release Notes](#release-notes)
- [License](#license)
- [Support](#support)

## Purpose

This role provides a reusable UFW policy layer without embedding hostnames,
network ranges, interfaces, or service ports. Role consumers define the
allowlist through `firewall_rules`.

The role manages:

- UFW package installation
- incoming, outgoing, and routed default policies
- serial application of allow, deny, reject, or limit rules
- logging level
- enabled or disabled runtime state
- the UFW systemd service
- post-apply runtime validation

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Debian-family Linux |
| Tested OS | Debian 13 Trixie on `arm64` |
| Ansible | `ansible-core >= 2.17` |
| Collection | `community.general >= 13.1.0` |
| Privilege escalation | Required |
| Network | Required only when installing the package |

Install the collection dependency:

```sh
ansible-galaxy collection install community.general:13.1.0
```

## Installation

After the role is published to Ansible Galaxy:

```sh
ansible-galaxy role install marcomc.firewall
```

Pinned install example:

```sh
ansible-galaxy role install marcomc.firewall,0.1.0
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `firewall_manage_package` | `true` | Install the UFW package |
| `firewall_package_name` | `ufw` | Package name |
| `firewall_manage_defaults` | `true` | Manage default policies |
| `firewall_default_incoming_policy` | `deny` | Incoming default policy |
| `firewall_default_outgoing_policy` | `allow` | Outgoing default policy |
| `firewall_default_routed_policy` | `deny` | Routed default policy |
| `firewall_rules` | `[]` | Ordered UFW rule mappings |
| `firewall_manage_logging` | `true` | Manage UFW logging |
| `firewall_logging` | `low` | UFW logging level |
| `firewall_manage_state` | `true` | Manage UFW runtime state |
| `firewall_state` | `enabled` | `enabled` or `disabled` |
| `firewall_manage_service` | `true` | Manage the UFW systemd unit |
| `firewall_service_name` | `ufw.service` | UFW systemd unit |
| `firewall_validate` | `true` | Validate UFW and systemd state |

See `defaults/main.yml` and `meta/argument_specs.yml` for the complete variable
contract.

## Rule Definitions

Each `firewall_rules` item maps directly to supported
`community.general.ufw` rule fields.

| Field | Purpose |
| --- | --- |
| `rule` | `allow`, `deny`, `limit`, or `reject` |
| `direction` | `in`, `out`, or `routed` |
| `interface` | Interface used by the selected direction |
| `interface_in`, `interface_out` | Interfaces for routed rules |
| `from_ip`, `from_port` | Source address and port |
| `to_ip`, `to_port` | Destination address and port |
| `proto` | Protocol such as `tcp` or `udp` |
| `name` | UFW application profile |
| `comment` | Operator-readable rule comment |
| `log` | Log new connections matched by the rule |
| `route` | Apply the rule to forwarded traffic |
| `delete` | Delete the matching rule |
| `insert`, `insert_relative_to` | Control rule position |

## Example Playbook

```yaml
---
- name: Configure host firewall
  hosts: all
  roles:
    - role: marcomc.firewall
      vars:
        firewall_rules:
          - rule: allow
            from_ip: 192.0.2.0/24
            to_port: "22"
            proto: tcp
            comment: Allow SSH from management LAN
          - rule: allow
            direction: in
            interface: tailscale0
            comment: Allow tailnet ingress
          - rule: allow
            to_port: "41641"
            proto: udp
            comment: Allow direct Tailscale UDP
```

## Supported Platforms

| Platform | Status |
| --- | --- |
| Debian 13 / Raspberry Pi OS Trixie | Live-tested |
| Debian 12 / Raspberry Pi OS Bookworm | Metadata-supported |

## Behavior

Rules are applied serially in list order because UFW does not support
concurrent rule updates.

UFW rule state is additive. Removing an item from `firewall_rules` does not
remove the existing host rule. Set the same rule with `delete: true` in a
bounded migration run, verify removal, then remove that migration entry. The
role intentionally does not reset the whole firewall during steady-state runs.

IPv6 equivalents are created by UFW when IPv6 is enabled and a rule is not
restricted to an IPv4 address.

## Tailscale Integration

The role does not change Tailscale's netfilter mode. Tailscale's default `on`
mode accepts traffic arriving through `tailscale0`, prevents spoofed CGNAT
traffic, and accepts its protocol traffic before ordinary host rules.

An explicit `allow in on tailscale0` UFW rule matches Tailscale's documented
UFW integration and makes the host policy clear. Tailnet grants and ACLs remain
the authoritative control over which tailnet identities may reach the host.

## Validation

```sh
ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

## Release Notes

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT.

## Support

Open issues against the standalone role repository after publication. Until
then, treat this role as a local project role.

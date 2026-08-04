# Ansible Galaxy Wi-Fi Watchdog Role Assessment

## Question

Could PiServ use an existing Ansible Galaxy role instead of maintaining a
custom NetworkManager Wi-Fi connectivity watchdog?

## Findings

| Candidate | Scope | Fit |
| --- | --- | --- |
| [`Aisbergg.networkmanager`](https://github.com/Aisbergg/ansible-role-networkmanager) | Installs/configures NetworkManager and manages connection profiles through `nmcli` | Useful for NetworkManager configuration, but does not monitor link, gateway, DNS, or perform progressive recovery |
| `jtyr.ansible_networkmanager` | Installs NetworkManager | Does not provide connectivity-health recovery |
| [`whiskerlabs.watchdog`](https://github.com/whiskerlabs/ansible-watchdog) | Installs/configures the Linux kernel `watchdog` daemon | Different failure model; the source repository is archived and it does not recover NetworkManager connectivity |
| `danmilon.watchdog` and `drum7.watchdog` | Configure the Linux kernel watchdog daemon | Different failure model; not a NetworkManager recovery controller |

The local `wifi_watchdog` role is warranted because it owns a distinct and
operationally important policy: it verifies a connected NetworkManager Wi-Fi
interface, a reachable gateway, and DNS resolution, then escalates from the
connection to NetworkManager. Host reboot remains disabled unless a consumer
explicitly enables it, and then uses a separate route-agnostic internet probe
instead of the Wi-Fi interface state.

## Evidence

`ansible-galaxy role search` on 2026-07-31 returned only two Debian-filtered
NetworkManager roles: `jtyr.ansible_networkmanager` and
`Aisbergg.networkmanager`. The latter's upstream README describes installation,
configuration, and connection management, and declares a dependency on
`community.general`; it does not describe a connectivity monitor or recovery
state machine.

The Galaxy watchdog search returned `danmilon.watchdog`, `drum7.watchdog`, and
`whiskerlabs.watchdog`. The upstream `whiskerlabs` README states that it
installs the `watchdog` Debian package and manages `/etc/watchdog.conf`; its
repository was archived on 2023-03-16. A kernel watchdog addresses an unresponsive
host or hardware-watchdog policy, not a host whose Wi-Fi stack remains running
while an access point or mesh node rejects association.

## Decision

Keep the standalone `wifi_watchdog` role. Do not add either category as a
runtime dependency:

- A NetworkManager configuration role would add a broad, unrelated ownership
  boundary to the current PiServ connection profile.
- A kernel-watchdog role could be evaluated later as a separate host-liveness
  control, but it must not replace network-specific recovery.

## Sources

- [Ansible Galaxy CLI role search and role information](https://docs.ansible.com/projects/ansible/latest/cli/ansible-galaxy.html)
- [Aisbergg NetworkManager role upstream README](https://github.com/Aisbergg/ansible-role-networkmanager)
- [Whisker Labs watchdog role upstream README](https://github.com/whiskerlabs/ansible-watchdog)
- [Ansible Galaxy developer guide: standalone roles](https://docs.ansible.com/projects/ansible/latest/galaxy/dev_guide.html)

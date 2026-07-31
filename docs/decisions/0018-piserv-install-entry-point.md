# 0018: PiServ Installation Entry Point

## Status

Accepted on 2026-07-28.

## Context

PiServ has dedicated playbooks for network access, host policy, hardware,
storage, and workloads. Reapplying them individually makes ordering easy to
miss and does not provide one repeatable convergence command.

Some playbooks are intentionally not steady-state configuration: NVMe migration
can repartition a disk, while pCloud health validation depends on manually
bootstrapped credentials.

## Decision

`scripts/run-piserv-install.sh` is the canonical full-host installation and
convergence entry point after manual bootstrap. It invokes
`ansible/playbooks/piserv-install.yml`, rejects partial-execution controls, and
then begins with read-only external-storage preflight before importing the
steady-state playbooks in this order:

1. External storage preflight
2. Tailscale
3. Firewall
4. Base host policy, including system mail
5. Wi-Fi connectivity watchdog
6. External storage
7. Freenove hardware
8. pCloud installation
9. Home Assistant MQTT Agent
10. Jackett
11. RaiPlaySound

The NVMe migration and pCloud health-check playbooks remain separate operator
entry points. Individual configuration playbooks also remain available for
narrow maintenance and recovery work.

## Consequences

- A converged PiServ host should report `changed=0` when the entry point is
  rerun.
- External storage identity, Freenove vendor source, and the non-empty
  Home Assistant MQTT Agent configuration are explicit first-install
  prerequisites. Tailscale login and pCloud credential bootstrap also remain
  manual. On a new host, install each runtime with its dedicated playbook
  before completing its manual authentication, then run the full entry point;
  credentials are never stored in Git.
- A failed mDNS lookup must use an operator-supplied `PISERV_IP` override for
  direct-IP recovery rather than a hard-coded address.
- The wrapper rejects tags, task-start and interactive-step controls, and
  Ansible tag environment controls. Direct `ansible-playbook` use of the full
  entrypoint is an unsupported bypass; individual playbooks remain available
  for documented narrow maintenance and recovery work.

## Validation

On 2026-07-28, one full live application completed with `ok=408`, `changed=0`,
and no failures. A subsequent rerun was interrupted by controller-side mDNS
resolution before it could establish the second idempotence result. Repeat the
validation with the current operator-supplied DHCP lease through the documented
direct-IP override.

## References

- [PiServ installation runbook](../runbooks/piserv-install.md)
- [PiServ README](../../README.md)

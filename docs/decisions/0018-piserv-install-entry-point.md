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

`ansible/playbooks/piserv-install.yml` is the canonical full-host installation
and convergence entry point after manual Tailscale and pCloud bootstrap. It
imports the steady-state playbooks in this order:

1. Tailscale
2. Firewall
3. Base host policy, including system mail
4. External storage
5. Freenove hardware
6. pCloud installation
7. Home Assistant MQTT Agent
8. Jackett
9. RaiPlaySound

The NVMe migration and pCloud health-check playbooks remain separate operator
entry points. Individual configuration playbooks also remain available for
narrow maintenance and recovery work.

## Consequences

- A converged PiServ host should report `changed=0` when the entry point is
  rerun.
- Tailscale login and pCloud credential bootstrap remain explicit manual
  prerequisites. On a new host, install each runtime with its dedicated
  playbook before completing its manual authentication, then run the full
  entry point; credentials are never stored in Git.
- A failed mDNS lookup must use an operator-supplied `PISERV_IP` override for
  direct-IP recovery rather than a hard-coded address.

## Validation

On 2026-07-28, one full live application completed with `ok=408`, `changed=0`,
and no failures. A subsequent rerun was interrupted by controller-side mDNS
resolution before it could establish the second idempotence result. Repeat the
validation with the current operator-supplied DHCP lease through the documented
direct-IP override.

## References

- [PiServ installation runbook](../runbooks/piserv-install.md)
- [PiServ README](../../README.md)

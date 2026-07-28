# PiServ Installation and Convergence

## Table of Contents

- [Purpose](#purpose)
- [Prerequisites](#prerequisites)
- [Apply](#apply)
- [Rerun and Idempotence](#rerun-and-idempotence)
- [Included Playbooks](#included-playbooks)
- [Excluded Playbooks](#excluded-playbooks)
- [Validation](#validation)
- [Observed Result](#observed-result)

## Purpose

Use `ansible/playbooks/piserv-install.yml` as the repeatable entry point for
installing and reconciling a manually bootstrapped PiServ host. The entry point
owns orchestration order; the existing roles and playbooks remain the
implementation of each policy.

## Prerequisites

Install the pinned Galaxy dependencies:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
```

Ensure the inventory can reach PiServ as `admin`. For a first installation,
complete the required manual bootstrap before running the full entry point:

1. Apply `ansible/playbooks/tailscale.yml`, then complete the Tailscale login
   described in the [Tailscale access runbook](tailscale-access.md).
2. Apply `ansible/playbooks/pcloudcc-install.yml` to install the client. It
   stops before user-service management until a saved pCloud session exists.
3. Complete the pCloud credential bootstrap in the
   [pCloud storage runbook](pcloudcc-storage.md), then rerun
   `ansible/playbooks/piserv-install.yml`.

Tailscale and pCloud credentials are never stored in Git or Ansible variables.

## Apply

Run the full installation and convergence entry point:

```sh
ansible-playbook ansible/playbooks/piserv-install.yml
```

The playbook fails at the first unsuccessful policy rather than hiding an
ordering or prerequisite problem.

## Rerun and Idempotence

The included configuration playbooks are expected to be idempotent. Run the
entry point again after a successful apply or after an operator change:

```sh
ansible-playbook ansible/playbooks/piserv-install.yml
```

When the host already matches the repository state, the second run should
report `changed=0`. A non-zero change count is evidence of drift, a newly
required dependency, or a task that needs investigation; it is not a reason to
silence the report.

Use check mode as an early signal, not as the only acceptance test. The pinned
Tailscale role is skipped in check mode because it parses an internally skipped
runtime command; PiServ still probes an existing Tailscale binary, service, and
preferences read-only.

```sh
ansible-playbook --check --diff ansible/playbooks/piserv-install.yml
```

## Included Playbooks

The entry point imports these playbooks in order:

1. `tailscale.yml`
2. `firewall.yml`
3. `piserv-base.yml`
4. `external-storage.yml`
5. `freenove-post-os.yml`
6. `pcloudcc-install.yml`
7. `ha-mqtt-agent.yml`
8. `jackett.yml`
9. `raiplaysound-cli-daily-sync.yml`

The order keeps Tailscale and the firewall ready before the base playbook's
listener preconditions, and installs pCloud before the RaiPlaySound workload
that depends on its mount health.

## Excluded Playbooks

`migrate-sd-to-nvme.yml` is excluded because it can repartition and format a
disk when explicitly enabled. Run it only through its dedicated migration
procedure.

`pcloudcc-health-check.yml` is excluded because it is a read-only operator
validation step that depends on manual pCloud authentication. Run it separately
after the pCloud service is available:

```sh
ansible-playbook ansible/playbooks/pcloudcc-health-check.yml
```

## Validation

Validate the entry point and the project playbooks before applying changes:

```sh
ansible-lint ansible/playbooks/piserv-install.yml
ansible-playbook --syntax-check ansible/playbooks/piserv-install.yml
ansible-playbook --syntax-check ansible/playbooks/*.yml
```

After a live apply, repeat the entry point and confirm the second run reports
`changed=0`, then run the workload-specific health checks and runbooks.

## Observed Result

On 2026-07-28, the entry point completed against PiServ with:

```text
ok=408 changed=0 unreachable=0 failed=0
```

A subsequent rerun was interrupted during the Freenove controller-copy task
when the controller could no longer resolve `piserv.local`; it did not report a
configuration failure. To repeat the full validation after an mDNS failure, use
the current DHCP lease supplied by the operator directly:

```sh
export PISERV_IP=<current-dhcp-lease>
ansible-playbook -e "ansible_host=${PISERV_IP}" \
  ansible/playbooks/piserv-install.yml
```

Follow-up: rerun the entry point through that direct-IP override and confirm a
second full recap with `changed=0`.

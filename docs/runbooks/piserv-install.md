# PiServ Installation and Convergence

## Table of Contents

- [Purpose](#purpose)
- [Prerequisites](#prerequisites)
- [Apply](#apply)
- [Rerun and Idempotence](#rerun-and-idempotence)
- [Included Playbooks](#included-playbooks)
- [Excluded Playbooks](#excluded-playbooks)
- [Validation](#validation)

## Purpose

Use `ansible/playbooks/piserv-install.yml` as the repeatable entry point for
installing and reconciling the PiServ host. The entry point owns orchestration
order; the existing roles and playbooks remain the implementation of each
policy.

## Prerequisites

Install the pinned Galaxy dependencies:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
```

Ensure the inventory can reach PiServ as `admin` and that the operator has
completed manual steps that cannot be stored in Git, including Tailscale login
and pCloud credential bootstrap when those workloads are enabled.

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

Use check mode as an early signal, not as the only acceptance test:

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

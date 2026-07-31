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

Use `scripts/run-piserv-install.sh` as the repeatable entry point for installing
and reconciling a manually bootstrapped PiServ host. It invokes
`ansible/playbooks/piserv-install.yml` and owns orchestration order; the
existing roles and playbooks remain the implementation of each policy.

## Prerequisites

Install the pinned Galaxy dependencies:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
```

Ensure the inventory can reach PiServ as `admin`. For a first installation,
complete the required manual bootstrap before running the full entry point:

1. Attach the prepared external disk with its unique `external-data`
   filesystem label. Use the read-only
   [device-identity discovery procedure](external-storage.md#configure-device-identity)
   to create the ignored `ansible/vars/external-storage.yml` file. The preflight
   discovers the partition and parent disk at runtime, then refuses zero or
   multiple candidates or an identity mismatch.
2. Create the ignored Freenove controller source with the
   [vendor-resource procedure](../../README.md#vendor-resources).
3. Restore the non-empty `/etc/ha-mqtt-agent/config.toml` from the approved
   secure source, as required by the
   [Home Assistant MQTT Agent runbook](ha-mqtt-agent.md).
4. Apply `ansible/playbooks/tailscale.yml`, then complete the Tailscale login
   described in the [Tailscale access runbook](tailscale-access.md).
5. Apply `ansible/playbooks/pcloudcc-install.yml` to install the client. It
   stops before user-service management until a saved pCloud session exists.
6. Complete the pCloud credential bootstrap in the
   [pCloud storage runbook](pcloudcc-storage.md), then rerun
   `scripts/run-piserv-install.sh`.

Tailscale and pCloud credentials are never stored in Git or tracked Ansible
variables. Tailscale may receive a private runtime auth key when required;
pCloud credential bootstrap remains manual.

## Apply

Run the full installation and convergence entry point:

```sh
scripts/run-piserv-install.sh
```

The wrapper rejects `--tags`, `-t`, `--skip-tags`, `--start-at-task`, `--step`,
`ANSIBLE_RUN_TAGS`, and `ANSIBLE_SKIP_TAGS`, because each can bypass required
storage, networking, and firewall ordering. It forwards safe full-run options
such as `--check`, `--diff`, `--limit`, and `-e`. Direct `ansible-playbook` use
of the full entrypoint is an unsupported bypass; use individual playbooks only
for documented narrow maintenance and recovery work.

The playbook fails at the first unsuccessful policy rather than hiding an
ordering or prerequisite problem.

## Rerun and Idempotence

The included configuration playbooks are expected to be idempotent. Run the
entry point again after a successful apply or after an operator change:

```sh
scripts/run-piserv-install.sh
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
scripts/run-piserv-install.sh --check --diff
```

## Included Playbooks

The entry point imports these playbooks in order:

1. `external-storage-preflight.yml`
2. `tailscale.yml`
3. `firewall.yml`
4. `piserv-base.yml`
5. `wifi-watchdog.yml`
6. `external-storage.yml`
7. `freenove-post-os.yml`
8. `pcloudcc-install.yml`
9. `ha-mqtt-agent.yml`
10. `jackett.yml`
11. `raiplaysound-cli-daily-sync.yml`

The storage preflight rejects an invalid identity before any host mutation.
The remaining order keeps Tailscale and the firewall ready before the base
playbook's listener preconditions, configures Wi-Fi recovery with the base host
policy, and installs pCloud before the RaiPlaySound workload that depends on
its mount health.

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
# Export PISERV_IP to the operator-supplied current DHCP lease before this block.
: "${PISERV_IP:?Set PISERV_IP to the operator-supplied current DHCP lease}"
ssh -o BatchMode=yes -o ConnectTimeout=10 "admin@${PISERV_IP}" 'sudo -n true'
scripts/run-piserv-install.sh -e "ansible_host=${PISERV_IP}"
```

Follow-up: rerun the entry point through that direct-IP override and confirm a
second full recap with `changed=0`.

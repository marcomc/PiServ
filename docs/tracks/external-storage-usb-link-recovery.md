# External SSD USB Link Recovery Plan

## Table of Contents

- [Status](#status)
- [Objective](#objective)
- [Evidence Log](#evidence-log)
- [Policy Decisions](#policy-decisions)
- [Target Boot Flow](#target-boot-flow)
- [Scope](#scope)
- [Implementation Phases](#implementation-phases)
- [Systemd Ordering Contract](#systemd-ordering-contract)
- [Safety Constraints](#safety-constraints)
- [Validation Matrix](#validation-matrix)
- [Rollout](#rollout)
- [Rollback](#rollback)
- [Documentation Follow-up](#documentation-follow-up)

## Status

| Field | Value |
| --- | --- |
| State | Planned; not implemented |
| Priority | High |
| Target | PiServ external ASM246X storage link |
| Filesystem | `external-data` mounted at `/mnt/external-data` |
| Backlog | [TODO: Automate ASM246X USB 3 link recovery before mount](../../TODO.md#propositions) |

## Objective

Detect whether the ASM246X bridge initially negotiates at `5000` or `480` Mbps
after USB enumeration and before `systemd-fsck` or the filesystem mount. When it
negotiates at `480` Mbps, attempt one bounded logical recovery while the
filesystem is inactive. If the same verified device still negotiates at `480`
Mbps, mount it in a degraded but available state and emit an explicit warning.

This plan extends the identity and mount policy in
[Decision 0017](../decisions/0017-external-ssd-storage.md). It does not change
the filesystem, partition layout, or stored data.

## Evidence Log

The 2026-08-05 investigation established the following behavior on the live
PiServ host:

- The bridge used the same physical Raspberry Pi USB port and xHCI controller
  when it appeared as either a `5000` Mbps SuperSpeed device or a `480` Mbps
  high-speed device.
- Retained boot journals contained 45 ASM246X enumerations: 34 at `5000` Mbps
  and 11 at `480` Mbps. Both speeds occurred across multiple kernel versions.
- A controlled test cleanly unmounted `/mnt/external-data`, logically rebound
  the isolated xHCI controller, and restored the same ASM246X serial and
  filesystem UUID at `5000` Mbps without a physical disconnect.
- Post-recovery SMART, ext4, mount-option, and kernel-error checks passed. The
  removal still emitted a SCSI cache-synchronization warning, reinforcing that
  recovery must occur before filesystem activation.

The successful test proves that logical recovery is viable on this host. It
does not distinguish a retained host-controller state from marginal USB signal
quality, and it does not establish a cause for the earlier unclean host stop.

## Policy Decisions

| Condition | Action |
| --- | --- |
| Verified device at `5000` Mbps | Do not reset; continue to filesystem check and mount |
| Verified device at `480` Mbps | Attempt one logical recovery before filesystem activation |
| Recovery returns the same device at `5000` Mbps | Continue to filesystem check and mount normally |
| Recovery is unsafe, fails, or returns the same device at `480` Mbps | Continue with a degraded mount and emit a high-visibility warning |
| Device identity or filesystem layout does not match | Do not reset or mount; fail closed |
| Configured disk is absent | Preserve bounded `nofail` boot behavior; do not reset unrelated hardware |
| Link issue appears after mounting | Report it; do not automatically unmount or reset active storage |

Only one recovery attempt is permitted per boot. Repeated controller resets are
never an acceptable fallback.

## Target Boot Flow

```text
kernel and udev enumerate USB storage
                |
                v
discover label, parent controller, identity, and USB speed
                |
        +-------+-------+
        |               |
     5000 Mbps        480 Mbps
        |               |
        |        one bounded xHCI rebind
        |               |
        |       re-enumerate and revalidate
        |               |
        +-------+-------+
                |
       same device at final speed
                |
        +-------+-------+
        |               |
     5000 Mbps        480 Mbps
        |               |
   normal status    degraded warning
        |               |
        +-------+-------+
                |
          systemd-fsck
                |
                v
     mount /mnt/external-data
                |
                v
       dependent services start
```

## Scope

Included:

- read-only discovery of the configured filesystem and its USB parent;
- pre-mount link-speed classification;
- one logical xHCI recovery attempt when the verified link is at `480` Mbps;
- degraded-mount reporting and boot evidence in persistent journald;
- systemd ordering, Ansible management, tests, rollback, and documentation.

Excluded:

- physical USB power cycling or cable diagnosis;
- filesystem repair, formatting, repartitioning, or SMART self-tests;
- runtime resets after `/mnt/external-data` is mounted;
- automatic host reboot after a failed recovery;
- changes intended to explain or remediate the earlier unclean host stop.

## Implementation Phases

### Phase 1: Define the helper contract

- Separate read-only classification, recovery, and boot orchestration so each
  behavior can be tested independently.
- Discover the device through the unique `external-data` label and verify the
  expected model and serial from ignored local variables.
- Resolve the USB device, negotiated speed, and owning xHCI controller through
  sysfs. Do not depend on `/dev/sda`, `usb 1-1`, or another transient name.
- Define structured outcomes for normal, degraded, absent, identity mismatch,
  unsafe controller, recovery failure, and recovery success states.

### Phase 2: Build the bounded recovery primitive

- Install a root-owned helper under a project libexec path.
- Provide a read-only check mode that cannot write to sysfs.
- Refuse recovery when the filesystem is mounted, the identity is uncertain,
  or unrelated USB devices share the controller.
- Use a per-boot lock and attempt marker, bounded enumeration and bind timeouts,
  and a cleanup trap that attempts to restore the controller binding.
- After re-enumeration, verify the label, model, serial, filesystem UUID, parent
  controller, and final link speed before returning success.

### Phase 3: Prove systemd orchestration

- Add a pre-mount oneshot gate initiated by the external-storage mount path.
- Hold both the relevant `systemd-fsck` instance and the mount unit until link
  classification and any recovery attempt finish.
- Preserve `nofail` and the bounded device-timeout behavior when the disk is
  absent.
- Ensure dependent services cannot start against an unmounted fallback
  directory.
- Avoid raw udev reset actions: re-enumeration can recursively trigger rules and
  race queued filesystem jobs.

### Phase 4: Codify in Ansible

- Add explicit enable, expected-speed, recovery-attempt, and timeout variables
  with range and relationship assertions.
- Render the helper and systemd artifacts from project-local templates.
- Keep device serials and filesystem UUIDs in ignored host-local variables.
- Make normal convergence and Ansible check mode deployment-only: neither may
  reset the controller.
- Support a complete disable path that restores the current fstab-generated
  mount behavior.

### Phase 5: Validate and roll out

- Validate rendered shell with ShellCheck and systemd artifacts with
  `systemd-analyze verify`.
- Validate fresh and converged Ansible check mode plus a second normal
  convergence.
- Prove the dependency graph and all safety outcomes before enabling automatic
  recovery at boot.
- Complete live reboot tests with SSH, mount, dependent-service, SMART, ext4,
  and prior-boot journal verification.

## Systemd Ordering Contract

The required order is:

```text
USB device available
  -> PiServ external link preflight and optional recovery
  -> systemd-fsck for the verified filesystem
  -> mnt-external\x2ddata.mount
  -> services using /mnt/external-data
```

Ordering only before the mount unit is insufficient because systemd may queue
the filesystem check concurrently. The implementation must explicitly prove
that neither `systemd-fsck` nor the mount accesses the device while an xHCI
rebind makes it disappear and reappear.

The current mount is generated from fstab. The implementation phase must first
prove that a generated mount dependency and targeted drop-ins provide the
required behavior. If that graph cannot be made deterministic, use a managed
custom orchestration path while retaining UUID-based mounting and the existing
absent-disk policy.

## Safety Constraints

- Require the unique filesystem label plus expected model and serial before any
  recovery mutation.
- Revalidate the filesystem UUID and identity after every re-enumeration.
- Refuse recovery while any child filesystem is mounted.
- Refuse a controller reset when unrelated devices would be disconnected.
- Permit at most one attempt per boot and serialize concurrent invocations.
- Bound every wait, retry, and systemd service duration.
- Restore the controller binding after partial failure where possible.
- Never reset by transient block-device or USB-bus name.
- Never run recovery from periodic monitoring after the filesystem is active.
- Record boot ID, initial speed, action, outcome, final speed, and mount policy
  as bounded single-line journal fields.
- Treat an identity or layout mismatch as blocking; degraded availability only
  applies to the expected device with a link-speed problem.

## Validation Matrix

| Scenario | Expected result |
| --- | --- |
| Verified device initially at `5000` Mbps | No-op; filesystem check and mount proceed |
| Verified device initially at `480` Mbps; recovery succeeds | One rebind; same identity at `5000`; mount proceeds |
| Verified device initially at `480` Mbps; recovery remains at `480` | No second reset; warning emitted; degraded mount proceeds |
| Recovery is unsafe because another controller device is present | No reset; warning emitted; verified disk mounts degraded |
| Disk is absent | Bounded wait; host boot continues; mount remains absent |
| Model, serial, UUID, label, or layout mismatches | No reset and no mount |
| Helper is invoked while the filesystem is mounted | Read-only status allowed; recovery refused |
| Unbind or bind fails | Cleanup attempted; timeout bounded; no retry loop |
| Gate starts twice in one boot | Lock and attempt marker prevent a second reset |
| Ansible runs normally or in check mode | Artifacts converge; controller is not reset |
| Link state is checked after mount | Telemetry only; no automatic recovery |
| Host reboots after successful or degraded path | SSH, mount policy, dependent services, journal, SMART, and ext4 state verified |

## Rollout

1. Deploy classification and journal telemetry with recovery disabled.
2. Validate one normal `5000` Mbps boot and the absent-disk timeout behavior.
3. Deploy the recovery helper but keep automatic boot invocation disabled;
   repeat a controlled manual proof with the filesystem inactive.
4. Enable the pre-mount gate after the systemd dependency graph passes static
   and live validation.
5. Observe multiple boots. Preserve the first natural `480` Mbps event and its
   recovery evidence before declaring the automation complete.

Automatic enablement must remain an explicit policy variable throughout the
rollout.

## Rollback

- Disable the pre-mount gate and automatic recovery variable.
- Remove its mount and filesystem-check ordering dependencies through Ansible.
- Reload systemd and verify the original UUID-backed, `nofail` mount path.
- Leave the read-only diagnostic helper available only if it has no ordering or
  runtime side effects.
- Reboot once and verify SSH, `/mnt/external-data`, dependent services, and the
  journal before closing rollback.

Rollback must not alter the filesystem, partition table, mount data, or ignored
device-identity values.

## Documentation Follow-up

After live implementation and validation:

- update [Decision 0017](../decisions/0017-external-ssd-storage.md) with the
  accepted link-recovery and degraded-availability policy;
- add operator checks, journal queries, disablement, and manual recovery to the
  [external-storage runbook](../runbooks/external-storage.md);
- update `CHANGELOG.md` with the shipped capability;
- check off the linked TODO actions only after their validation gates pass;
- append exact commands, observed results, and follow-up actions to this track's
  evidence section or the operational runbook.

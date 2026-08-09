# PiServ Agent Instructions

Follow `$HOME/AGENTS.md` for canonical user-wide policy.

## Project Context

- Canonical repository path: `$HOME/Development/RaspberryPi/PiServ`.
- Purpose: configure and reproduce the PiServ Raspberry Pi server.
- Status: work in progress; backward compatibility is not required yet.
- Target host: `PiServ.local`.
- Target IP: DHCP-assigned; resolve `PiServ.local` before direct-IP diagnostics.
- For mDNS-failure recovery, require an operator-supplied current DHCP lease in
  `PISERV_IP` and use it directly for both SSH and Ansible fallback commands;
  never hard-code or resolve the fallback address through mDNS.
- Hardware: Raspberry Pi 5, 4 GB RAM, 128 GB NVMe SSD.
- Current network: Wi-Fi only.
- Future network: Ethernet may be added.
- Sudo user: `admin`.
- Access model: SSH key-based access from this host is allowed.

## Operating Rules

- Treat the Raspberry Pi as the production test target.
- Test setup changes directly on `PiServ.local` before marking them done.
- Prefer the simplest live command that proves the intended state.
- After a live setup step is correct, codify it in Ansible and, where useful,
  supporting shell scripts.
- Keep runbooks, decisions, and validation notes current with every meaningful
  setup change.
- Do not preserve compatibility with obsolete local decisions unless the user
  explicitly asks for it.

## Automation Rules

- Ansible should become the authoritative reproduction path once the live setup
  is understood.
- When integrating an external role, declare its required collections and make
  the privilege-escalation boundary explicit. Validate the integration from a
  clean dependency installation before live application.
- Keep reusable Ansible roles under `ansible/roles/` suitable for possible
  Ansible Galaxy publication.
- Exception: `ansible/roles/base` is the project-local PiServ host baseline role.
  It may carry PiServ-specific policy, service names, defaults, and documentation,
  and is not intended for standalone Galaxy publication.
- Reusable roles must stay agnostic of the PiServ project: no PiServ hostnames,
  IPs, local repository paths, private assumptions, or project-only defaults in
  role tasks, defaults, templates, metadata, tests, or role documentation.
- Put PiServ-specific values for reusable roles in project playbooks, inventory,
  group variables, runbooks, or decision records instead of embedding them in
  those roles.
- Shell scripts should wrap repeatable operator commands, preflight checks, or
  narrow tasks that do not fit cleanly in Ansible.
- Keep automation idempotent where practical.
- Before rendering a configurable timeout, retry, interval, or escalation value
  into shell or service configuration, assert its explicit range and every
  required relationship to related values; cover invalid values and ordering.
- When validating required managed files with `ansible.builtin.stat`, assert
  that the result exists before reading nested metadata; cover an otherwise
  compatible fixture with the required marker absent.
- Name every top-level `import_playbook` entry in orchestration playbooks so
  Ansible Lint validates the full entry point.
- When a PiServ playbook overrides a generic role's package or plugin set,
  declare expected runtime registrations explicitly and guard live probes in
  check mode when the service is absent; validate both fresh and converged
  check-mode paths.
- Keep reusable storage policy tracked, but source serials, filesystem UUIDs,
  persistent device paths, and other host-specific identities from ignored
  local variables or a secure external source; use tracked placeholders only.
- Before destructive disk changes, enumerate the configured disk and every
  current child device, and refuse the operation if any is mounted. Install
  every target-side package required by storage modules only after these safety
  checks and before the first dependent module task.
- For stateful storage, validate concrete device identity, filesystem layout,
  and mount conflicts before package, group-membership, ACL, or service
  mutations. A placeholder fallback configuration must fail without changing
  host state.
- For permanently attached SuperSpeed storage, record the negotiated link speed
  at boot and do not attribute USB 2 fallback on a paired xHCI root-hub path to
  filesystem or workload behavior without first checking the physical link.
- Before reinitializing a USB controller to recover storage speed, verify that
  it has no unrelated devices or open handles; sync and unmount the filesystem,
  then verify the expected device identity before remounting.
- Keep one-off migration cleanup out of steady-state playbooks after the live
  host reaches the new source of truth. Use a bounded migration command or
  temporary playbook for teardown, then remove it and update diagnostics to
  check the replacement artifact.
- Do not stage executable helpers at predictable fixed paths under `/tmp`. Stream
  short remote helpers over SSH stdin, use `mktemp -d` with restrictive
  ownership, or install privileged helpers under a root-owned project libexec
  path.
- When role variables accept arbitrary config file paths, stat the parent
  directory before creating it. Create missing private parents, but do not
  change ownership or mode of an existing system directory such as `/tmp` or
  `/etc` unless the role explicitly owns that directory.
- For numeric role settings rendered into timeout, retry, or recovery logic,
  validate the uncast value and cross-setting ordering before applying an
  `int` filter; invalid input must not silently become zero.
- For boot-time services that deliver through an external DNS-dependent
  transport, treat `network-online.target` as insufficient readiness. Do not
  perform unbounded DNS or metadata work before the bounded delivery path; use
  local identity where sufficient, otherwise include the prerequisite work in
  the service timeout. Retry only identified temporary delivery failures with
  a bounded policy, and leave permanent failures visible to systemd.
- Before escalating an interface-recovery failure to an automatic host reboot,
  distinguish the normal policy route from every eligible IPv4 default-route
  interface. Prove that each route is unavailable, and cover the failed
  preferred-route plus healthy alternate-route case in regression tests.
- Negative Ansible tests that rely on `block`/`rescue` must fail explicitly
  after an unexpected success and assert that the rescued failure came from
  the intended validation task. For configurable systemd units, render a
  non-default policy and assert the effective consuming directive, not only
  template source text.
- Document any intentionally non-idempotent operation in the relevant runbook.
- Do not commit secrets, private keys, tokens, or host-specific credentials.
- Keep real Wi-Fi SSIDs and NetworkManager profile names in ignored local vars;
  tracked playbooks must use generic examples and fail clearly when required
  local values are absent.
- Before describing a wildcard listener as LAN-only, account for interface-wide
  firewall rules and validate every permitted ingress path, including Tailnet.
- Treat `vendor/` as upstream reference material. Do not rewrite vendored files
  solely to satisfy project lint rules unless PiServ intentionally forks or
  patches that upstream code.
- When a role supports multiple source-delivery modes, do not patch the delivered
  checkout in place. Render a separate validated runtime artifact and prove
  source-copy plus render convergence on a second run. Reject source and
  destination filesystem aliases, including those reached through a symlinked
  parent directory, before replacing an artifact.
- Before changing a boot command line, fail closed unless the stable rollback
  backup and any current-kernel reboot control are distinct private regular
  files with valid content. Reject both path and inode aliases before mutation,
  then activate and verify any required current-kernel reboot mode before
  changing the persistent command line or scheduling an automatic reboot.
- For a managed vendor adaptation, render a separate deterministic runtime
  artifact instead of editing the delivered source. Select it only in the
  enabled service path, remove it when disabled, compare content and metadata,
  and use structural validation plus enable/disable, unrelated-match, and
  permission-drift regressions before restarting the service.
- Normalize journal-derived command, user, and other fields to bounded
  single-line text before interpolating them into plain-text notifications.
  Bound the record count and accept command attribution only for the intended
  operation class.
- For an abrupt host stop, classify the last journal entry as correlation only
  until retained pre-stop CPU, memory, temperature, I/O, and power or reset
  telemetry establishes causation. Capture that bounded evidence before further
  high-memory or hardware-stability testing.
- Before increasing local-model address-space limits, verify that the cgroup v2
  memory controller and effective systemd limits are enforcing containment.
  Keep an independently effective `LimitAS` cap when cgroup memory controls
  are unavailable.
- For configurable privileged lifecycle artifacts, inventory every root,
  output, staging, persistent, backup, recovery, cleanup, and runtime-consumer
  path before mutation. Authenticate parent containment and inode identity,
  publish atomically, and prove the eventual service identity has the required
  access before enabling scheduled consumption.

## pCloud / FUSE Rules

- For `pcloudcc` on Debian arm64, pin the upstream source revision and carry
  documented patches in Ansible instead of editing `/opt` manually.
- Generate role-managed source patches from a clean or known checkout with
  `git diff`; do not hand-write unified diff hunks.
- Before automating `pcloudcc` mounts for a TOTP-enabled account, validate the
  bootstrap path explicitly. If login fails, inspect then remove
  `/tmp/psync_err.log` because it may contain authentication-derived material.
- For role tasks that manage FUSE mount roots, detect active mounts first and
  skip root-side directory ownership or creation tasks while the user mount is
  active; validate the mounted state separately.

## Documentation Rules

- Update `README.md` when the project purpose, layout, access model, or core
  workflow changes.
- Update `TODO.md` when planned setup work is discovered, completed, or dropped.
- Update `CHANGELOG.md` for meaningful project changes.
- Add runbooks under `docs/runbooks/`.
- Add architecture or operational decisions under `docs/decisions/`.
- Include the command run, observed result, and follow-up action in runbooks
  when documenting live server changes.

## Validation

- Run `markdownlint --config "$HOME/.markdownlint.json"` on every
  Markdown file created or changed.
- Run `shellcheck --enable=all` on every shell script created or changed.
- Render every new Jinja shell template and run ShellCheck on the rendered
  output before deployment; avoid or isolate Jinja delimiter sequences in
  embedded shell syntax.
- Set `check_mode: false` on read-only command tasks whose output is used by
  assertions, so `ansible-playbook --check` evaluates live state rather than
  skipped task results.
- Exclude unmodified upstream files under `vendor/` from first-party lint
  gates. If a vendored file is intentionally patched, document the patch and
  validate that file too.
- Before declaring work complete, report which validation commands passed and
  any checks that were not applicable.

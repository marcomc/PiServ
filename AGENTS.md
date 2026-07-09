# PiServ Agent Instructions

Follow `$HOME/AGENTS.md` for canonical user-wide policy.

## Project Context

- Canonical repository path: `$HOME/Development/RaspberryPi/PiServ`.
- Stale repository path: `$HOME/Development/RaspberryPi/PiServ`.
  Do not use it for commands, downloads, or generated files.
- Purpose: configure and reproduce the PiServ Raspberry Pi server.
- Status: private work in progress; backward compatibility is not required yet.
- Target host: `piserv.example.com`.
- Target IP: `192.0.2.181`.
- Hardware: Raspberry Pi 5, 4 GB RAM, 128 GB NVMe SSD.
- Current network: Wi-Fi only.
- Future network: Ethernet may be added.
- Sudo user: `operator`.
- Access model: SSH key-based access from this host is allowed.

## Operating Rules

- Treat the Raspberry Pi as the production test target.
- Test setup changes directly on `piserv.example.com` before marking them done.
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
- Do not stage executable helpers at predictable fixed paths under `/tmp`. Stream
  short remote helpers over SSH stdin, use `mktemp -d` with restrictive
  ownership, or install privileged helpers under a root-owned project libexec
  path.
- When role variables accept arbitrary config file paths, stat the parent
  directory before creating it. Create missing private parents, but do not
  change ownership or mode of an existing system directory such as `/tmp` or
  `/etc` unless the role explicitly owns that directory.
- Document any intentionally non-idempotent operation in the relevant runbook.
- Do not commit secrets, private keys, tokens, or host-specific credentials.
- Treat `vendor/` as upstream reference material. Do not rewrite vendored files
  solely to satisfy project lint rules unless PiServ intentionally forks or
  patches that upstream code.

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
- Exclude unmodified upstream files under `vendor/` from first-party lint
  gates. If a vendored file is intentionally patched, document the patch and
  validate that file too.
- Before declaring work complete, report which validation commands passed and
  any checks that were not applicable.

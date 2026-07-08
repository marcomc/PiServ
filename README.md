# PiServ

PiServ is the setup and recovery project for a Raspberry Pi 5 server at
`piserv.example.com` / `192.0.2.181`.

## Table of Contents

- [Purpose](#purpose)
- [Local Repository](#local-repository)
- [Server Facts](#server-facts)
- [Access](#access)
- [Operating Model](#operating-model)
- [Repository Layout](#repository-layout)
- [Vendor Resources](#vendor-resources)
- [Storage Direction](#storage-direction)
- [Implementation Tracks](#implementation-tracks)
- [Automation](#automation)
- [Initial Workflow](#initial-workflow)
- [Validation](#validation)

## Purpose

This repository captures the live setup, automation, runbooks, and decisions
needed to operate and reproduce the PiServ Raspberry Pi server.

## Local Repository

Use this local repository path for all commands, downloads, and generated files:

```text
$HOME/Development/RaspberryPi/PiServ
```

Do not use the old renamed path:

```text
$HOME/Development/RaspberryPi/PiServ
```

## Server Facts

| Item | Value |
| --- | --- |
| Hostname | `piserv.example.com` |
| IP address | `192.0.2.181` |
| Hardware | Raspberry Pi 5 |
| RAM | 4 GB |
| Storage | 128 GB NVMe SSD |
| Current network | Wi-Fi |
| Future network | Ethernet may be added |
| Sudo user | `operator` |
| Access | SSH key-based access from this host |

## Access

Primary SSH targets:

```sh
ssh operator@piserv.example.com
ssh operator@192.0.2.181
```

Use `piserv.example.com` when mDNS resolution is healthy. Use the IP address when
validating network or name-resolution issues.

## Operating Model

PiServ is production-first: live commands are tested directly on the server,
then converted into repeatable automation once the desired state is confirmed.

The current project is private and work in progress. Backward compatibility is
not a constraint until the project is prepared for public reuse.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Project-specific agent rules and server context |
| `README.md` | Operator entry point |
| `TODO.md` | Current setup backlog |
| `CHANGELOG.md` | Project change history |
| `LICENSE` | Private-use license notice |
| `docs/` | Runbooks, decisions, and supporting documentation |
| `docs/runbooks/` | Step-by-step operational procedures |
| `docs/decisions/` | Durable setup and architecture decisions |
| `docs/tracks/` | Implementation checklists for active workstreams |
| `ansible/` | Inventory and playbooks |
| `scripts/` | Operator scripts and remote helpers |
| `vendor/` | Downloaded upstream references and third-party setup material |

## Vendor Resources

Freenove FNK0100 resources are stored locally under `vendor/freenove/`.
That path is intentionally ignored by Git.

Recreate the Freenove content with:

```sh
mkdir -p vendor/freenove
git clone https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi.git \
  vendor/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi
```

The local copy currently includes `Tutorial.pdf`, `Installing Raspberry Pi
OS.pdf`, Freenove case-control code, images, and the MS51FB9AE datasheet.

Freenove publishes these files under Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 Unported. Keep this resource private
and use it as a vendor reference unless licensing is reviewed for broader use.

Vendored upstream files are not first-party project code. Do not edit them for
project lint conformance unless PiServ intentionally forks or patches them.

## Storage Direction

Podcast-producing jobs should use pCloud-backed storage only after the official
pCloud setup is validated on PiServ.

Current decision:

| Rank | Option | Recommendation |
| --- | --- | --- |
| 1 | Official `pcloudcc` FUSE mount | Selected backend for scheduled podcast jobs |
| 2 | Official pCloud Drive AppImage | Future manual/touchscreen option only |
| 3 | Local NVMe staging plus WebDAV sync | Fallback when `pcloudcc` is not reliable |

Selected pCloud settings:

| Item | Value |
| --- | --- |
| pCloud account email | Operator-provided; do not store in docs |
| pCloud data region | European Union |
| pCloud mount root | `/mnt/pcloud` |
| RaiPlaySound podcast target | `/mnt/pcloud/My Music/Podcasts/raiplaypodcast` |

The mount is expected to expose the user's full pCloud account for now.
Folder-scoped pCloud accounts or shared-folder-only access are out of scope for
the current setup.

Do not plan around pCloud rsync until pCloud releases official rsync support.

## Implementation Tracks

Active implementation tracks:

| Track | Purpose |
| --- | --- |
| [pCloud `pcloudcc` podcast storage](docs/tracks/pcloudcc-podcast-storage.md) | Build, validate, and automate the pCloud mount for scheduled podcast output |

## Automation

Configure the PiServ base host policy:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
```

The base playbook manages SSH root-login and password-auth policy, disables
unneeded CUPS, `rpcbind`, and NFS helper units, enables unattended upgrades, and
disables cloud-init.

Configure the Freenove FNK0100K post-OS setup:

```sh
ansible-playbook ansible/playbooks/freenove-post-os.yml
```

The Freenove playbook installs runtime packages, enables I2C, clones the
official Freenove code from the controller-managed local vendor copy into
`/opt/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi`, creates desktop
launchers, enables the Freenove background service, manages `Code/app_config.json`
for LED/fan/OLED startup behavior, and validates Python imports/source syntax.
It reboots only when the I2C firmware setting changes.

Install the pCloud console client:

```sh
ansible-playbook ansible/playbooks/pcloudcc-install.yml
```

The pCloud playbook installs the source-built `pcloudcc` binary, applies the
Debian 13 `arm64` build patch and CLI TOTP prompt patch, prepares
`/mnt/pcloud`, and validates the installed client against the role's
`pcloudcc_version` default. After manual `pcloudcc -p -s -t` login, it also
hardens `~operator/.pcloud` and manages a credential-free user service for the
mount. It does not perform pCloud credential login.

Validate the pCloud mount before scheduled podcast work:

```sh
scripts/check-pcloudcc-health.sh
ansible-playbook ansible/playbooks/pcloudcc-health-check.yml
```

Install and manage the RaiPlaySound daily podcast sync:

```sh
ansible-playbook ansible/playbooks/raiplaysound-cli-daily-sync.yml
```

The RaiPlaySound playbook installs the pinned CLI source revision for `operator`,
writes the PiServ config, installs a user-scoped daily systemd timer, and gates
the direct-write sync on the pCloud health check.

Migrate a microSD-booted PiServ system to NVMe:

```sh
scripts/migrate-sd-to-nvme.sh --yes --reboot
```

Run the same migration through Ansible:

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/migrate-sd-to-nvme.yml \
  -e allow_destructive_nvme_reimage=true
```

Both paths repartition and format `/dev/nvme0n1`. Use them only when the Pi is
booted from microSD and the NVMe drive is the intended destructive target.

## Initial Workflow

1. Verify SSH access and sudo behavior on the live server.
2. Capture a baseline inventory of OS, kernel, storage, network, users, and
   enabled services.
3. Apply small live setup changes directly on the server.
4. Record the command, result, and reasoning in a runbook or decision document.
5. Convert confirmed setup into Ansible playbooks or shell scripts.
6. Re-run automation against the server and document validation.

## Validation

Run Markdown validation after documentation changes:

```sh
markdownlint --config "$HOME/.markdownlint.json" AGENTS.md README.md TODO.md CHANGELOG.md docs/**/*.md
```

Run ShellCheck on shell scripts when any are added or changed:

```sh
shellcheck --enable=all scripts/*.sh
```

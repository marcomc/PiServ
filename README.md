# PiServ

PiServ is the setup and recovery project for a Raspberry Pi 5 server at
`PiServ.local`.

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

## Server Facts

| Item | Value |
| --- | --- |
| Hostname | `PiServ.local` |
| IP address | DHCP-assigned; resolve the hostname before direct-IP diagnostics |
| Hardware | Raspberry Pi 5 |
| RAM | 4 GB |
| Storage | 128 GB NVMe SSD + 4 TB USB 3 external SSD |
| Current network | Wi-Fi |
| Future network | Ethernet may be added |
| Sudo user | `admin` |
| Access | SSH key-based access from this host |

## Access

Primary SSH targets:

```sh
ssh admin@PiServ.local
```

Use `PiServ.local` when mDNS resolution is healthy. Resolve the current IP before
validating network or name-resolution issues.

## Operating Model

PiServ is production-first: live commands are tested directly on the server,
then converted into repeatable automation once the desired state is confirmed.

The current project is work in progress. Backward compatibility is not a
constraint until the project is prepared for public reuse.

This private working repository intentionally records PiServ's live host
identifiers for direct operations. Before any public release, sanitize the
inventory, documentation, and retained Git history.

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
  vendor/freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi-main
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

PiServ also has a PiServ-owned external data volume at `/mnt/external-data`.
It uses one journaled ext4 partition labeled `external-data`, with a shared
`shared/` directory and a restricted `backups/` directory. See the [external
SSD runbook](docs/runbooks/external-storage.md) for permissions, service
access, and recovery.

## Implementation Tracks

Active implementation tracks:

| Track | Purpose |
| --- | --- |
| [pCloud `pcloudcc` podcast storage](docs/tracks/pcloudcc-podcast-storage.md) | Build, validate, and automate the pCloud mount for scheduled podcast output |
| [External SSD storage](docs/runbooks/external-storage.md) | Operate the PiServ-owned ext4 volume for shared data and backups |

## Automation

### Full PiServ installation

Use `ansible/playbooks/piserv-install.yml` as the repeatable PiServ
installation and convergence entry point after the required manual Tailscale
and pCloud bootstrap:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
ansible-playbook ansible/playbooks/piserv-install.yml
```

The entry point imports the steady-state configuration playbooks in dependency
order: Tailscale, firewall, base host policy, external storage, Freenove,
pCloud, Home Assistant MQTT Agent, Jackett, and RaiPlaySound. It is designed
to be rerun; a converged second run should report `changed=0` apart from live
state that has drifted.

The NVMe migration playbook is intentionally excluded because it is destructive
and one-time. The pCloud health-check playbook is also separate because it is
an operator validation step and depends on manual credential bootstrap.
See the [PiServ installation runbook](docs/runbooks/piserv-install.md) for the
first-install sequence, full ordering, validation, and mDNS-recovery procedure.

After Tailscale and the firewall policy are active, configure the PiServ base
host policy:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
```

The base playbook applies the dedicated `msmtp` role first, then manages SSH
root-login and password-auth policy, keeps VNC aligned with touchscreen output
`DSI-1`, exposes the Cockpit HTTPS console on port `9090`, provides an
authenticated Glances API to the LAN and Home Assistant, disables unneeded
CUPS, `rpcbind`, and NFS helper units, enables unattended upgrades, and disables
cloud-init. PiServ uses `msmtp` with operator-managed `/etc/msmtprc` and
`/etc/aliases` files because they contain SMTP credentials and local delivery
policy. Boot notifications are skipped until `/etc/msmtprc` exists and is
non-empty. Unattended upgrades send a mobile-readable routine digest with
package version transitions; full logs remain on PiServ and native error alerts
remain enabled as a fallback.

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
hardens `~admin/.pcloud` and manages a credential-free user service for the
mount. It does not perform pCloud credential login.

Validate the pCloud mount before scheduled podcast work:

```sh
scripts/check-pcloudcc-health.sh
ansible-playbook ansible/playbooks/pcloudcc-health-check.yml
```

Install the pinned external role and collection dependencies:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
```

Install Tailscale and start `tailscaled`:

```sh
ansible-playbook ansible/playbooks/tailscale.yml
```

The Tailscale playbook uses the `artis3n.tailscale.machine` Galaxy collection
role to install `tailscale` and enable `tailscaled`. Tailnet login remains a
manual runbook step unless a private runtime auth key is supplied. PiServ uses
standard OpenSSH; Tailscale SSH is not enabled. PiServ advertises its local IPv4
LAN as a high-availability subnet router, while rejecting imported subnet routes
so local replies remain on the physical LAN.

Configure and enable the PiServ firewall:

```sh
ansible-playbook ansible/playbooks/firewall.yml
```

The firewall playbook uses a commit-pinned PiServ fork of `oefenweb.ufw` for
generic UFW configuration. PiServ-owned imported tasks verify prerequisites,
enforce the UFW service state, and assert the applied runtime policy. The role
remains the source of truth for its managed UFW configuration, policies, and
rules. PiServ permits SSH, VNC, Cockpit HTTPS, and mDNS from its current IPv4
LAN; the Glances API from the same LAN; all ingress through `tailscale0`; and
UDP port `41641` for direct Tailscale peer connections. It permits routed
tailnet traffic only to its local IPv4 LAN. Other LAN IPv6 ingress remains
denied by default. Docker-published services use separate `DOCKER-USER` rules
because Docker port forwarding bypasses UFW's normal input chain.

Deploy Jackett and FlareSolverr:

```sh
ansible-playbook ansible/playbooks/jackett.yml
```

The Jackett playbook applies the local, Galaxy-ready `jackett_search` role.
The role uses the upstream Makefile to install the CLI plus its Jackett and
FlareSolverr containers, retaining upstream `latest` image tags. Persistent
Compose files, Jackett state, and the private CLI config are owned by `admin`
under `/home/admin/.config/jackett-search`. PiServ adds only the Docker-aware
TCP `9117` ingress policy: the current IPv4 LAN and `tailscale0` are allowed,
and other published-port access is dropped. See the
[Jackett runbook](docs/runbooks/jackett.md) for tracker configuration,
validation, updates, and recovery.

Install and manage the RaiPlaySound daily podcast sync:

```sh
ansible-playbook ansible/playbooks/raiplaysound-cli-daily-sync.yml
```

The RaiPlaySound playbook installs the pinned CLI source revision for `admin`,
creates the PiServ config when missing, installs a user-scoped daily systemd
timer, and gates the direct-write sync on the pCloud health check. New configs
send summary mail to local recipient `root` through the system `msmtp` config
wrapper; existing create-only configs must be edited manually. Current
user-scoped workloads run under the single human sudo account `admin`.

Install and validate the Home Assistant MQTT Agent:

```sh
ansible-playbook ansible/playbooks/ha-mqtt-agent.yml
```

The playbook installs Galaxy role `marcomc.ha_mqtt_agent` version `v0.1.1`,
pins the upstream agent to version `0.3.0`, preserves the operator-managed MQTT
configuration, and validates the active service, broker connectivity, and
Raspberry Pi 5 firmware telemetry in the service security context.

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
markdownlint --config "$HOME/.markdownlint.json" $(rg --files -g '*.md' -g '!vendor/**')
```

Run ShellCheck on tracked shell scripts, extensionless shebang helpers, and
rendered shell templates:

```sh
scripts/validate-shell.sh
```

Run the full static Ansible gate before release:

```sh
ansible-lint ansible/playbooks ansible/roles
for playbook in $(rg --files ansible/playbooks -g '*.yml' | sort); do
  ansible-playbook --syntax-check "$playbook"
done
for test_playbook in $(find ansible/roles -path '*/tests/test.yml' -print | sort); do
  role_dir=${test_playbook%/tests/test.yml}
  (cd "$role_dir" && ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml)
done
```

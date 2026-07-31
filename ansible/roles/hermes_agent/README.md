# Ansible Role: hermes_agent

Install a locked-down [Nous Hermes Agent](https://github.com/NousResearch/hermes-agent)
service backed by the OpenAI Codex CLI. The role pins and verifies both upstream
artifacts, runs Hermes as an unprivileged system user, keeps the dashboard on
loopback, and can schedule encrypted-state backups to a caller-provided path.

This directory is prepared for later extraction into the planned
`marcomc.hermes_agent` Galaxy role. It is not published to Galaxy yet.

## Table of Contents

- [Requirements](#requirements)
- [Security Posture](#security-posture)
- [Installation](#installation)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Provider Login](#provider-login)
- [Backups](#backups)
- [Local Models](#local-models)
- [Testing](#testing)
- [Release](#release)
- [License](#license)

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Debian 12 (Bookworm) or Debian 13 (Trixie) |
| Target CPU | ARM64 (`aarch64` or `arm64`) |
| Ansible | `ansible-core >= 2.16` |
| Privilege escalation | Required |
| Network | HTTPS access to the pinned Hermes and Codex release artifacts |

The default role policy deliberately supports only the `openai-codex` provider
and a loopback-bound dashboard. It does not authenticate the provider or store
account credentials.

## Security Posture

The default CLI allowlist contains only `memory` and `skills`. Their write paths
still require operator approval. Terminal, file, browser, code execution, Home
Assistant, and all other bundled toolsets are disabled.

Hermes runs as the non-login `hermes-agent` system user. Its systemd services
use a private state directory, `NoNewPrivileges`, a cleared capability set, and
a strict read-only system filesystem with explicit writable paths.

The dashboard binds to `127.0.0.1`. Reach it through an authenticated SSH tunnel
or a separately-managed authenticated reverse proxy. Do not expose the dashboard
directly by changing its bind address.

## Installation

After the role has been extracted and imported into Galaxy, install a pinned
release:

```sh
ansible-galaxy role install marcomc.hermes_agent,0.1.0
```

Until then, include the local role by its role directory name:

```yaml
---
- name: Install Hermes Agent
  hosts: arm64_hosts
  become: true
  roles:
    - role: hermes_agent
```

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `hermes_agent_user` | `hermes-agent` | Dedicated non-login runtime user. |
| `hermes_agent_group` | `hermes-agent` | Runtime group. |
| `hermes_agent_home` | `/var/lib/hermes-agent` | Private persistent state. |
| `hermes_agent_install_dir` | `/usr/local/lib/hermes-agent` | Root-owned Hermes checkout. |
| `hermes_agent_binary_path` | `/usr/local/bin/hermes` | Hermes CLI installed by upstream. |
| `hermes_agent_repo_version` | pinned commit | Hermes upstream commit to install. |
| `hermes_agent_version` | `0.19.0` | Expected Hermes CLI version. |
| `hermes_agent_installer_url` | pinned upstream URL | Hermes installer URL. |
| `hermes_agent_installer_path` | `/usr/local/libexec/hermes-agent-installer` | Local installer path. |
| `hermes_agent_installer_checksum` | pinned SHA-256 | Installer integrity check. |
| `hermes_agent_supported_architectures` | `aarch64`, `arm64` | CPU architectures permitted by the role. |
| `hermes_agent_packages` | role list | Debian package prerequisites. |
| `hermes_agent_model` | `gpt-5.5` | Hermes default model. |
| `hermes_agent_provider` | `openai-codex` | Provider accepted by role policy. |
| `hermes_agent_enabled_toolsets` | `memory`, `skills` | Explicit CLI allowlist. |
| `hermes_agent_disabled_toolsets` | role list | Explicitly disabled bundled toolsets. |
| `hermes_agent_dashboard_host` | `127.0.0.1` | Dashboard bind address. |
| `hermes_agent_dashboard_port` | `9119` | Dashboard port. |
| `hermes_agent_dashboard_service_name` | `hermes-agent-dashboard.service` | Dashboard systemd unit. |
| `hermes_agent_manage_dashboard` | `true` | Build and run the dashboard. |
| `hermes_agent_codex_version` | `0.145.0` | Codex CLI release version. |
| `hermes_agent_download_cache_dir` | `/var/cache/hermes-agent` | Verified-download cache. |
| `hermes_agent_codex_archive_url` | pinned upstream URL | ARM64 Codex archive URL. |
| `hermes_agent_codex_archive_checksum` | pinned SHA-256 | Codex archive integrity check. |
| `hermes_agent_codex_archive_binary_name` | `codex-aarch64-unknown-linux-musl` | Binary name in the archive. |
| `hermes_agent_codex_install_dir` | versioned path | Root-owned Codex installation directory. |
| `hermes_agent_codex_binary_path` | `/usr/local/bin/codex` | Active Codex CLI symlink. |
| `hermes_agent_codex_home` | `{{ hermes_agent_home }}/codex` | Private Codex state directory. |
| `hermes_agent_manage_backup` | `false` | Install a scheduled Hermes-state backup timer. |
| `hermes_agent_backup_group` | empty | Existing group permitted to access the backup path. |
| `hermes_agent_backup_dir` | `/var/backups/hermes-agent` | Backup archive directory. |
| `hermes_agent_backup_service_name` | `hermes-agent-backup.service` | Backup systemd service. |
| `hermes_agent_backup_timer_name` | `hermes-agent-backup.timer` | Backup systemd timer. |
| `hermes_agent_backup_retention_days` | `30` | Retention period for backup ZIP files. |
| `hermes_agent_backup_on_calendar` | `*-*-* 03:20:00` | systemd calendar schedule. |
| `hermes_agent_backup_timezone` | `UTC` | Time zone used by the schedule. |
| `hermes_agent_backup_randomized_delay` | `30m` | Maximum random start delay. |
| `hermes_agent_manage_local_models` | `false` | Install pinned local llama.cpp benchmark services. |
| `hermes_agent_local_model_packages` | role list | Debian packages used by the benchmark helper. |
| `hermes_agent_local_model_runtime_version` | `b9637` | llama.cpp runtime version. |
| `hermes_agent_local_model_runtime_archive_url` | pinned upstream URL | ARM64 llama.cpp archive URL. |
| `hermes_agent_local_model_runtime_archive_checksum` | pinned SHA-256 | Runtime archive integrity check. |
| `hermes_agent_local_model_runtime_dir` | versioned path | Root-owned llama.cpp installation directory. |
| `hermes_agent_local_model_llama_cli_path` | `/usr/local/bin/llama-cli` | Active llama.cpp CLI. |
| `hermes_agent_local_model_llama_server_path` | `/usr/local/bin/llama-server` | Active llama.cpp server. |
| `hermes_agent_local_models_dir` | sibling `hermes-models` directory | Model storage directory, kept outside Hermes state backups. |
| `hermes_agent_local_models_results_dir` | `benchmark-results` child | Benchmark result directory. |
| `hermes_agent_local_models_min_free_bytes` | `10737418240` | Required remaining free space after download. |
| `hermes_agent_local_models_host` | `127.0.0.1` | Local-model service bind address. |
| `hermes_agent_local_models_context_size` | `65536` | Context window used by services. |
| `hermes_agent_local_models_threads` | `3` | Inference and batch thread count. |
| `hermes_agent_local_models_benchmark_max_tokens` | `128` | Completion-token budget for the synthetic probe. |
| `hermes_agent_local_models_cache_type_k` | `q4_0` | Key-cache quantization for memory control. |
| `hermes_agent_local_models_cache_type_v` | `q4_0` | Value-cache quantization for memory control. |
| `hermes_agent_local_models_address_space_limit` | `4G` | Process address-space hard limit, independent of cgroup memory support. |
| `hermes_agent_local_models_memory_high` | `2500M` | systemd memory pressure threshold. |
| `hermes_agent_local_models_memory_max` | `3200M` | systemd memory hard limit. |
| `hermes_agent_local_models_memory_swap_max` | `512M` | systemd swap limit. |
| `hermes_agent_local_model_benchmark_helper_path` | `/usr/local/libexec/hermes-agent/benchmark-local-model` | Benchmark helper path. |
| `hermes_agent_local_models` | role list | Model records and their checksum-pinned sources. |

The full variable contract, including types, is in
[meta/argument_specs.yml](meta/argument_specs.yml).

## Example Playbook

```yaml
---
- name: Install a private Hermes Agent dashboard
  hosts: arm64_hosts
  become: true
  roles:
    - role: marcomc.hermes_agent
      vars:
        hermes_agent_manage_backup: true
        hermes_agent_backup_group: backups
        hermes_agent_backup_dir: /srv/backups/hermes-agent
        hermes_agent_backup_timezone: Europe/Rome
```

The backup group and directory are deployment values. Do not put host-specific
mount paths, credentials, or provider tokens into the role defaults.

## Provider Login

The role intentionally does not create credentials. Authenticate after the
deployment as the runtime user:

```sh
sudo -u hermes-agent -H env \
  HERMES_HOME=/var/lib/hermes-agent \
  CODEX_HOME=/var/lib/hermes-agent/codex \
  hermes auth add openai-codex
```

## Backups

When `hermes_agent_manage_backup` is true, the role creates a systemd timer that
runs `hermes backup`, retains archives for the configured number of days, and
uses `RequiresMountsFor` for the backup target. Set `hermes_agent_backup_group`
to an existing group that authorizes the runtime user to access the parent
storage path.

## Local Models

`hermes_agent_manage_local_models` is disabled by default. When enabled, the
role installs a pinned ARM64 llama.cpp release and checksum-pinned model files,
then provides one loopback-only systemd service per configured model. It does
not create, format, mount, or otherwise adopt storage.

Set `hermes_agent_local_models_dir` in the consuming playbook when models belong
on a dedicated volume. The role checks the filesystem containing that directory
for enough space for the configured files plus
`hermes_agent_local_models_min_free_bytes`.

## Testing

The embedded Molecule scenario uses local fixture artifacts. It does not fetch
Hermes, Codex, or use a provider account. Docker must be running.

```sh
uv venv --python 3.13
uv pip install --python .venv/bin/python -r requirements-dev.txt
.venv/bin/ansible-galaxy collection install -r molecule/default/collections.yml
.venv/bin/ansible-lint .
.venv/bin/molecule test
```

While the role remains nested in its current parent repository, run the commands
from this directory.

## Release

See [docs/releasing.md](docs/releasing.md). The guide applies after this role
directory is extracted into its own public repository; it does not publish or
import anything from the current parent repository.

## License

MIT. See [LICENSE](LICENSE).

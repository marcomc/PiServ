# Ansible Role: raiplaysound_cli

Install RaiPlaySound CLI and optionally manage a user-scoped daily sync timer.

## Table of Contents

- [Purpose](#purpose)
- [Requirements](#requirements)
- [Role Variables](#role-variables)
- [Example Playbook](#example-playbook)
- [Behavior](#behavior)
- [Validation](#validation)
- [License](#license)

## Purpose

This role automates the validated RaiPlaySound CLI install path:

- install Debian runtime packages
- check out the RaiPlaySound CLI source
- run the project's standalone `make install` path for a runtime user
- write an environment-style config file
- optionally manage a user-scoped systemd service and timer

## Requirements

| Requirement | Value |
| --- | --- |
| Target OS | Debian-family OS |
| Ansible | `ansible-core >= 2.15` |
| Privilege escalation | Required |
| Network | Target must reach GitHub, Debian package repositories, and PyPI |

## Role Variables

| Variable | Default | Description |
| --- | --- | --- |
| `raiplaysound_cli_runtime_user` | Remote user fact | User that owns the install |
| `raiplaysound_cli_source_dir` | `/opt/raiplaysound-cli` | Source checkout path |
| `raiplaysound_cli_repo_url` | GitHub repository URL | Source repository |
| `raiplaysound_cli_repo_version` | `main` | Git ref to check out |
| `raiplaysound_cli_expected_version` | empty | Optional version assertion |
| `raiplaysound_cli_config_path` | runtime user config dir | Config file path |
| `raiplaysound_cli_config_mode` | `managed` | Config behavior: `managed`, `create`, or `unmanaged` |
| `raiplaysound_cli_config_favorites` | `[]` | Favorites used by the default config |
| `raiplaysound_cli_config_defaults` | default CLI config map | Base config values |
| `raiplaysound_cli_config` | `{}` | Partial config overrides merged with defaults |
| `raiplaysound_cli_manage_user_timer` | `false` | Manage user service and timer |
| `raiplaysound_cli_timer_on_calendar` | `*-*-* 08:00:00` | Timer schedule |
| `raiplaysound_cli_service_exec_start_pre` | `[]` | Optional preflight commands |

See `defaults/main.yml` for the full variable set.

## Example Playbook

```yaml
---
- name: Install RaiPlaySound CLI
  hosts: raspberry_pi
  gather_facts: true
  roles:
    - role: marcomc.raiplaysound_cli
      vars:
        raiplaysound_cli_runtime_user: podcast
        raiplaysound_cli_manage_user_timer: true
        raiplaysound_cli_config:
          TARGET_BASE: /srv/podcasts/raiplaysound
          FAVORITES: musicalbox,profili
          RSS_FEED: true
```

## Behavior

The role installs the CLI for the selected runtime user under that user's
`~/.local/share/raiplaysound-cli` tree, matching the upstream `make install`
workflow.

The role does not manage mail credentials. If email-related config values are
omitted, the daily sync command still runs and skips the email summary.

`raiplaysound_cli_config` is intentionally partial. Values set there override
matching keys from `raiplaysound_cli_config_defaults`; omitted keys keep their
role defaults.

Config management modes:

| Mode | Variables | Behavior |
| --- | --- | --- |
| Managed | `raiplaysound_cli_config_mode: managed` | Rewrite config on every role run |
| Create-only | `raiplaysound_cli_config_mode: create` | Create config when missing, preserve existing edits |
| Unmanaged | `raiplaysound_cli_config_mode: unmanaged` | Never write config; assert it exists when managing the timer |

Use `raiplaysound_cli_service_exec_start_pre` to gate scheduled writes on a
site-specific mount or storage health check.

## Validation

```sh
ANSIBLE_ROLES_PATH=.. ansible-playbook --syntax-check tests/test.yml
ansible-lint .
```

## License

MIT. See `LICENSE`.

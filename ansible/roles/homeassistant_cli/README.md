# Home Assistant CLI Role

## Table of Contents

- [Purpose](#purpose)
- [Behavior](#behavior)
- [Variables](#variables)

## Purpose

Installs a pinned `homeassistant-cli` virtual environment and a wrapper for
authenticated REST and WebSocket API access to Home Assistant.

## Behavior

The caller supplies the runtime identity, server URL, and existing
operator-provisioned token environment file. The role does not create, copy, or
expose the token. The wrapper maps the configured token variable to
`HASS_TOKEN`, sets `HASS_SERVER`, and validates authenticated API read access
with `hass-cli info`.

The token file must contain exactly one unquoted `NAME=value` entry for the
configured token name. The wrapper reads that entry as data and never sources
the file as shell code.

The role constrains its managed files to a dedicated `/usr/local` runtime tree
and requires every virtualenv file to be root-owned. The runtime user receives
only the executable wrapper and its existing private token file.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `homeassistant_cli_runtime_user` | empty | Required user running the CLI. |
| `homeassistant_cli_runtime_group` | empty | Required group owning the token file. |
| `homeassistant_cli_install_dir` | `/usr/local/lib/homeassistant-cli` | Root-owned runtime parent. |
| `homeassistant_cli_package` | `homeassistant-cli==1.0.0` | Pinned PyPI package. |
| `homeassistant_cli_server` | empty | Home Assistant base URL. |
| `homeassistant_cli_token_env_file` | empty | Required private token file. |
| `homeassistant_cli_token_env_var` | `HASS_TOKEN` | Token variable sourced by the wrapper. |

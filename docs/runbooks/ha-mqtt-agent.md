# Home Assistant MQTT Agent

## Table of Contents

- [Purpose](#purpose)
- [Prerequisites](#prerequisites)
- [Apply](#apply)
- [Observed Result](#observed-result)
- [Recovery](#recovery)

## Purpose

Install and validate the Home Assistant MQTT Agent on PiServ while preserving
the operator-managed MQTT credentials in `/etc/ha-mqtt-agent/config.toml`.

## Prerequisites

- `PiServ.local` resolves and accepts SSH connections as `admin`.
- The non-empty config file is already present. Its credentials must never be
  committed or passed as Ansible extra variables.
- Galaxy dependencies are installed into `.ansible/roles`.

## Apply

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-playbook ansible/playbooks/ha-mqtt-agent.yml
```

The playbook pins Galaxy role `marcomc.ha_mqtt_agent` to `0.1.0` and its
upstream agent checkout to commit `57b8bfb907d3a7192ba6ba4fdf1337a28569cc25`
(`v0.3.0`). It preserves config content but enforces `root:ha-mqtt-agent` and
mode `0640`.

## Observed Result

On 2026-07-15, before the role integration, the host reported:

```text
ha-mqtt-agent.service: active (running), enabled
ha-mqtt-agent --version: 0.3.0
ha-mqtt-agent doctor --mqtt: mqtt: ok
vcgencmd pmic_read_adc EXT5V_V: 5.01428000V
```

The Ansible run must complete with the service active and the MQTT doctor check
passing in the `ha-mqtt-agent` service context.

## Recovery

If the service does not start, inspect it without reading or printing config
contents:

```sh
ssh admin@PiServ.local 'sudo systemctl status ha-mqtt-agent.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u ha-mqtt-agent.service -n 100 --no-pager'
```

Restore a known-good operator-managed config from the secure backup, then rerun
the playbook. Do not set `ha_mqtt_agent_config_management: managed` unless the
complete secret TOML is supplied from an approved secret source.

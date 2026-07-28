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
- `admin` can use non-interactive sudo. Verify with
  `ssh admin@PiServ.local 'sudo -n true'`.
- The non-empty config file is already present. Its credentials must never be
  committed or passed as Ansible extra variables.
- Galaxy dependencies are installed into `.ansible/roles`.

## Apply

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-playbook ansible/playbooks/ha-mqtt-agent.yml
```

If mDNS does not provide a usable SSH address, the operator must obtain the
current DHCP lease independently and export it as `PISERV_IP`. Do not resolve
the fallback through `PiServ.local` or store the DHCP address in inventory.
Require the value, then use it directly for both SSH and Ansible:

```sh
: "${PISERV_IP:?Set PISERV_IP to the operator-supplied current DHCP lease}"
ssh "admin@${PISERV_IP}" 'sudo -n true'
ansible-playbook ansible/playbooks/ha-mqtt-agent.yml -e "ansible_host=${PISERV_IP}"
```

The playbook pins Galaxy role `marcomc.ha_mqtt_agent` to `v0.1.1` and its
upstream agent checkout to commit `57b8bfb907d3a7192ba6ba4fdf1337a28569cc25`
(`v0.3.0`). It preserves config content but enforces `root:ha-mqtt-agent` and
mode `0640`.

## Observed Result

On 2026-07-16, a clean Galaxy installation of role `v0.1.1` was followed by one
check-mode run and two live runs. All three completed with
`ok=30 changed=0 failed=0`; the second live run confirmed idempotence.

```text
config metadata: root:ha-mqtt-agent, mode 0640
ha-mqtt-agent.service: enabled and active
ha-mqtt-agent --version: 0.3.0
ha-mqtt-agent --config /etc/ha-mqtt-agent/config.toml doctor --mqtt: mqtt: ok
vcgencmd get_throttled: throttled=0x0
vcgencmd pmic_read_adc EXT5V_V: passed in the service security context
```

Role `v0.1.1` also runs its read-only source and runtime probes during Ansible
check mode, so `ansible-playbook --check` validates the converged host without
reinstalling the agent or rewriting its configuration.

## Recovery

If the service does not start, inspect it without reading or printing config
contents:

```sh
ssh admin@PiServ.local 'sudo systemctl status ha-mqtt-agent.service --no-pager'
ssh admin@PiServ.local 'sudo journalctl -u ha-mqtt-agent.service -n 100 --no-pager'
ssh admin@PiServ.local 'sudo -u ha-mqtt-agent /usr/local/bin/ha-mqtt-agent --config /etc/ha-mqtt-agent/config.toml doctor --mqtt'
```

Restore a known-good operator-managed config from the secure backup, then rerun
the playbook. Do not set `ha_mqtt_agent_config_management: managed` unless the
complete secret TOML is supplied from an approved secret source.

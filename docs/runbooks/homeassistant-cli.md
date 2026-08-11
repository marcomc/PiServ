# Home Assistant CLI

## Purpose

Install and validate `homeassistant-cli` on PiServ using the existing private
Home Assistant token already provisioned for Hermes.

The CLI uses Home Assistant REST and WebSocket APIs. The Home Assistant Assist
MCP remains available separately as a secondary path.

## Ansible Galaxy assessment

On 2026-08-09, the searches below returned no Debian role matching installation
and configuration of the remote `homeassistant-cli` client:

```bash
ansible-galaxy role search 'homeassistant cli' --platforms Debian
ansible-galaxy role search 'hass cli' --platforms Debian
```

The local role is therefore generic: it requires its caller to provide a
runtime identity, Home Assistant server URL, and an existing private token
file. The Hermes user and token path are PiServ playbook configuration, not
role defaults.

## Preconditions

- PiServ resolves as `PiServ.local`. If mDNS fails, obtain the current DHCP
  lease independently and export it as `PISERV_IP`; never derive the fallback
  through mDNS.
- `ansible/vars/hermes-agent.yml` contains the private Home Assistant MCP URL.
- PiServ contains `/var/lib/hermes-agent/home-assistant-mcp.env`, owned by
  `hermes-agent:hermes-agent` with mode `0600`.

Validate an operator-supplied fallback directly for both SSH and Ansible:

```bash
repo_root="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/lib/piserv-target.sh
source "${repo_root}/scripts/lib/piserv-target.sh"
piserv_ip="$(piserv_ip_literal)"
piserv_target="$(piserv_ssh_target_from_ip "${piserv_ip}")"
ssh "${piserv_target}" 'sudo -n true'
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/homeassistant-cli.yml \
  -e "ansible_host=${piserv_ip}"
```

## Install and validate

Run from the repository root:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/homeassistant-cli.yml
```

The playbook derives the REST server URL by removing `/api/mcp` from the
configured MCP URL. It installs a pinned virtualenv at
`/usr/local/lib/homeassistant-cli/venv` and exposes the wrapper at
`/usr/local/bin/hass-cli`.

The wrapper reads the existing token file and maps `HASS_MCP_TOKEN` to the
`HASS_TOKEN` variable expected by `hass-cli`. The token is never written to
tracked files or command-line arguments.

The playbook validates both the CLI version and authenticated `hass-cli info`
read access. To run a later operator command as the Hermes runtime user:

```bash
sudo -u hermes-agent /usr/local/bin/hass-cli entity list
```

## Observed validation

On 2026-08-09, the playbook completed on PiServ with `changed=0` on its second
run. The authenticated CLI listed the available climate services, including
`set_hvac_mode`, `set_fan_mode`, `set_swing_mode`, and
`set_swing_horizontal_mode`:

```bash
ssh admin@PiServ.local \
  'sudo -u hermes-agent /usr/local/bin/hass-cli service list climate'
```

On the same date, Hermes completed an explicitly authorized reversible
acceptance test for `climate.camera_da_letto` through the dedicated wrapper:

1. It confirmed the initial state was `off` and turned the entity on.
2. It set target temperatures of 23 C and 25 C, verifying each result.
3. It set the supported `low` and `high` fan modes, verifying each result.
4. It turned the entity off; an independent `hass-cli state get` check
   confirmed the final state was `off`.

No other entity was addressed during the test.

## Recovery

If authentication fails, verify the Home Assistant URL and rotate the existing
token in Home Assistant. Replace only the private token file, then rerun the
playbook. Do not copy the token into Ansible variables, shell history, or Git.

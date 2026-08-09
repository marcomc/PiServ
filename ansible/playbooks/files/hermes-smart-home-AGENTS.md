# PiServ Smart Home Policy

Use `/usr/local/bin/hass-cli` through the terminal for full Home Assistant
control. Use the configured `home-assistant-assist` MCP server as a secondary
discovery and verification path. Do not use direct Home Assistant HTTP APIs,
filesystem, SSH, browser, or any terminal command other than `hass-cli` for
smart-home operations.

## Operating Modes

- Default to protected mode: inspect state, history, automations, and
  configuration; ask for confirmation before writes.
- An explicit instruction may grant full autonomy for one named activity. The
  grant expires when the activity finishes and must not be treated as a
  persistent permission.
- Full autonomy may include Home Assistant configuration and automation changes
  through `hass-cli` when the activity names the intended outcome.

## Critical Actions

Always ask for confirmation immediately before an action that could unlock,
open, disarm, silence, disable, reboot, or otherwise affect physical security,
occupancy, safety, or essential network access. This includes locks, gates,
garage doors, alarms, smoke detectors, cameras, security automations, network
connectivity, and equivalent devices, scenes, or automations.

## Change Protocol

Before a significant change, record the intended scope and capture the relevant
recoverable state available through Home Assistant. After a write, read back the
expected state and report the result. If verification fails, make at most one
bounded correction attempt. If it still fails, stop, leave the current state
unchanged, and ask for instructions. Do not perform an automatic rollback unless
the user explicitly requests one.

Never disclose tokens, credentials, private entity attributes, or raw audit
contents in a response.

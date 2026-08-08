# 0020: Hermes Home Assistant and Apple Home Release Scope

## Status

Accepted for `0.5.0` on 2026-08-08.

## Decision

PiServ will use Home Assistant as Hermes' operational gateway. Hermes receives
the full set of operations exposed by the Home Assistant MCP server, while
Home Assistant remains authoritative for entity exposure and operation policy.

Hermes uses a protected mode by default. An explicit instruction can grant
autonomy for the current activity only; the grant expires when that activity
ends. Physical security actions such as locks, alarms, gates, and other
security-critical operations still require confirmation even in that mode.

Before significant changes, Hermes must preserve the activity's bounded state
and audit intent, authorization, tools, entities, before/after state, result,
and errors without recording credentials. If a verification fails, Hermes may
attempt one bounded correction. If it still fails, Hermes stops and requests
instructions without automatically rolling back the current state.

The release acceptance test uses a local Mac harness. It sends a fixed prompt
to Hermes through the CLI over SSH, falls back to the authenticated dashboard
with Computer Use if the CLI cannot provide a stable non-interactive path, and
uses `homeclaw-cli` locally as a read-only Apple Home observer. It does not add
HomeClaw SSH or Supergateway to the Hermes runtime.

## Consequences

- The Hermes role does not need a new generic MCP abstraction for `0.5.0`.
- The Home Assistant Assist exposure policy is security-critical and must be
  reviewed before adding entities or operations.
- The acceptance fixture uses only an explicit local allowlist of reversible,
  non-critical entities.
- Scenes are inspected but not triggered by the generic harness because a
  safe automatic restoration contract is not available for arbitrary scenes.
- Apple Home-only entities remain outside the runtime path; HomeKit Bridge
  verifies Home Assistant entities flowing to Apple Home.
- The release cannot be considered passed while PiServ cannot reach the
  configured Home Assistant MCP endpoint.

## Validation

The implementation is provided by:

- [Hermes Home Assistant and Apple Home acceptance runbook](../runbooks/hermes-home-apple-home.md)
- [`verify-hermes-home-apple-home.py`](../../scripts/verify-hermes-home-apple-home.py)
- [`hermes-home-apple-home.example.json`](../../scripts/hermes-home-apple-home.example.json)

On 2026-08-08, the authenticated MCP probe discovered 21 Home Assistant tools.
The first full acceptance run changed the configured non-critical light from
`on` to `off` through Hermes, observed `off` in HomeClaw, then restored `on`
through Hermes and verified the restored state in both systems. The same proof
passed after a restart of `hermes-agent-dashboard.service`.

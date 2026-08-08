# Hermes Home Assistant and Apple Home Acceptance Test

## Table of Contents

- [Purpose](#purpose)
- [Prerequisites](#prerequisites)
- [Local Configuration](#local-configuration)
- [Run the Test](#run-the-test)
- [Test Contract](#test-contract)
- [Failure Handling](#failure-handling)
- [Dashboard Fallback](#dashboard-fallback)
- [Current Live Finding](#current-live-finding)

## Purpose

This runbook verifies the release path:

```text
Hermes CLI on PiServ
        |
        v
Home Assistant MCP and state API
        |
        v
HomeKit Bridge
        |
        v
Apple Home observed from the Mac
```

The test is an explicitly started release acceptance test. It is not a
permanent HomeClaw transport and does not add SSH or Supergateway to Hermes.

## Prerequisites

- `homeclaw-cli` is installed and authenticated on the Mac.
- `ssh admin@PiServ.local` works without an interactive password.
- Hermes is authenticated as `hermes-agent` on PiServ.
- The Hermes MCP configuration is enabled and points to the intended Home
  Assistant `/api/mcp` endpoint.
- The configured Home Assistant token file exists on PiServ and is readable
  only by `hermes-agent`.
- The selected Home Assistant entity is explicitly non-critical and reversible.
- The selected scene is safe to inspect without triggering it.

Check the non-mutating prerequisites:

```sh
homeclaw-cli status
ssh admin@PiServ.local \
  'sudo -u hermes-agent -H env HERMES_HOME=/var/lib/hermes-agent \
   CODEX_HOME=/var/lib/hermes-agent/codex hermes auth status openai-codex'
ssh admin@PiServ.local \
  'sudo -u hermes-agent -H env HERMES_HOME=/var/lib/hermes-agent \
   CODEX_HOME=/var/lib/hermes-agent/codex hermes mcp test home-assistant-assist'
```

The MCP test must resolve the configured Home Assistant hostname. A valid
Hermes login alone does not prove MCP reachability.

## Local Configuration

Create the ignored local configuration from the tracked example:

```sh
cp scripts/hermes-home-apple-home.example.json \
  scripts/hermes-home-apple-home.local.json
```

Set the real Home Assistant entity ID, HomeClaw accessory name, Home Assistant
API URL, and a scene that is safe to inspect. Keep the file local; entity names
and host-specific IDs are not part of the repository contract.

## Run the Test

Run a non-mutating preflight first:

```sh
python3 scripts/verify-hermes-home-apple-home.py --dry-run
```

Run the acceptance test only after the preflight passes:

```sh
python3 scripts/verify-hermes-home-apple-home.py
```

The command runs from the Mac. It invokes Hermes through `hermes chat --query`
over SSH, then uses `homeclaw-cli` locally to observe Apple Home. It polls both
Home Assistant and HomeClaw for up to 30 seconds by default.

Reports are written below the ignored path
`artifacts/hermes-home-apple-home/<timestamp>/` as `report.json` and
`report.txt`.

## Test Contract

The harness:

1. Validates the local allowlist and rejects any entity not marked
   `risk: non-critical`.
2. Checks HomeClaw readiness and verifies configured scenes without triggering
   them.
3. Captures the target state from Home Assistant and HomeClaw.
4. Sends a fixed, versioned prompt authorizing autonomy only for the current
   target entity.
5. Requires Hermes to use the Home Assistant MCP server and not touch other
   entities, automations, scenes, configuration, or security devices.
6. Verifies the requested state in Home Assistant and Apple Home.
7. Restores the original target state through Hermes and verifies both sides.
8. Produces a human-readable report and structured JSON without credentials.

The captured target state is the scoped test backup for this reversible
acceptance fixture. It does not replace a Home Assistant backup before a broad
configuration or automation change.

## Failure Handling

The test fails closed when authentication, MCP reachability, entity identity,
initial state consistency, or Apple Home propagation is unavailable. On a
mutation attempt it still performs fixture cleanup and marks cleanup failure
separately in the report.

If Home Assistant changes but Apple Home does not converge, the report records
the failure and the observed states. It does not retry by default. Inspect the
report before running another attempt.

Hermes' runtime policy remains separate: it may attempt one bounded correction,
then stop and ask for instructions while leaving the current state. The test
harness cleanup exists only to avoid leaving its own reversible fixture changed.

## Dashboard Fallback

If `hermes chat --query` cannot run a stable non-interactive request, use the
authenticated dashboard as the fallback driver:

```sh
ssh -N -L 9119:127.0.0.1:9119 admin@PiServ.local
```

Open `http://127.0.0.1:9119` with Computer Use, send the exact prompt recorded
in the test report, and then run the HomeClaw verification and cleanup steps
from the runbook. Do not enable HomeClaw writes or create a persistent Mac to
PiServ transport for this fallback.

## Current Live Finding

On 2026-08-08, PiServ reported valid `openai-codex` authentication and an
enabled `home-assistant-assist` MCP configuration, but the configured hostname
`home.piguard.home.arpa` did not resolve from PiServ. A read-only request to
the currently resolved address `192.168.1.253` returned HTTP `401`, confirming
that the HTTP service is reachable but not replacing the configured hostname
as a permanent fix. The dashboard fallback also reached its sign-in page but
had no authenticated browser session. The acceptance test is therefore not
yet a release pass. Resolve the DNS path and authenticate the approved test
driver first, then rerun the non-mutating preflight.

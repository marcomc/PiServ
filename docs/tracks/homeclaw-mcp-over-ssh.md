# HomeClaw MCP over SSH

## Table of Contents

- [Status](#status)
- [Scope](#scope)
- [Architecture](#architecture)
- [Operational Model](#operational-model)
- [Security Policy](#security-policy)
- [Implementation Phases](#implementation-phases)
- [Validation Gates](#validation-gates)
- [Rollback](#rollback)

## Status

Proposal. No deployment or SSH configuration is included in this track.

## Scope

Provide Hermes on PiServ with controlled access to the HomeKit MCP exposed by
HomeClaw on a Mac, using SSH as the authenticated transport. HomeClaw remains
the Apple Home gateway; PiServ remains the agent and policy boundary.

This proposal does not require OpenClaw. HomeClaw's CLI or stdio MCP server is
the integration surface.

## Architecture

```text
Hermes on PiServ
        |
        | local MCP client launches an SSH stdio transport
        v
SSH/Tailscale SSH to the Mac
        |
        | per-session remote command
        v
HomeClaw MCP adapter (stdio)
        |
        | Unix socket
        v
HomeClaw.app, started manually on macOS
        |
        v
Apple Home / HomeKit
```

The HomeClaw app must be running on the Mac and have HomeKit permission. The
MCP adapter communicates with that local app through its Unix socket. The
HomeClaw project documents the stdio MCP server and the local socket model in
its [architecture and MCP documentation](https://github.com/omarshahine/HomeClaw).

## Operational Model

An MCP stdio process cannot be attached remotely after it has been connected to
an arbitrary terminal. Therefore this design has one important distinction:

- the operator starts and leaves `HomeClaw.app` running on the Mac;
- each Hermes MCP session starts the adapter through SSH, for example with
  `node /Applications/HomeClaw.app/Contents/Resources/mcp-server.js`;
- PiServ does not start or manage the HomeClaw application itself.

If the adapter must also be started manually and remain persistent, this SSH
proposal is not sufficient by itself; use the Supergateway proposal instead.

The Mac may be unavailable. Hermes must treat SSH failure, HomeClaw socket
failure, and stale HomeKit data as gateway-unavailable states, not as evidence
that an accessory is off.

## Security Policy

- Use a dedicated macOS account or restricted SSH principal where practical.
- Prefer Tailscale SSH; otherwise use key-based SSH restricted to PiServ.
- Permit only the HomeClaw MCP adapter command, not an arbitrary shell.
- Keep HomeKit write tools disabled until read-only discovery is validated.
- Require explicit confirmation for locks, garages, security systems, scene
  replacement, and automation changes.
- Record caller, tool, target, requested mutation, result, and gateway identity
  in the PiServ audit trail.
- Keep the Mac host key and SSH credentials outside tracked files.

## Implementation Phases

1. Confirm the Mac can run HomeClaw.app, access the intended Apple Home, and
   accept an SSH connection from PiServ.
2. Establish a manual SSH command that starts the bundled HomeClaw MCP adapter
   and returns a valid MCP `initialize` response.
3. Add a PiServ MCP transport wrapper with fixed command arguments, bounded
   timeouts, reconnect handling, and structured error mapping.
4. Expose only read tools and validate homes, rooms, devices, scenes,
   automations, and recent events.
5. Add confirmed write tools, dry-run where available, post-write reads, and
   audit records.

## Validation Gates

- A PiServ-only test discovers the HomeKit home without exposing credentials.
- A Mac sleep, app close, SSH failure, and HomeKit permission failure each
  produce a bounded unavailable result.
- Hermes cannot alter the remote command or add arbitrary SSH arguments.
- Read operations do not change accessory state.
- A reversible device write succeeds only after confirmation and is verified by
  a second read.
- Scene and automation mutations are backed up or captured before change and
  verified afterward.

## Rollback

Disable the HomeClaw MCP server definition in Hermes and remove the SSH wrapper.
No Apple Home pairing or configuration change is required to roll back this
transport.

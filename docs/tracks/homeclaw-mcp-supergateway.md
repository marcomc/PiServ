# HomeClaw MCP with Supergateway

## Table of Contents

- [Status](#status)
- [Scope](#scope)
- [Architecture](#architecture)
- [Manual Startup](#manual-startup)
- [Network and Authentication](#network-and-authentication)
- [Implementation Phases](#implementation-phases)
- [Validation Gates](#validation-gates)
- [Rollback](#rollback)

## Status

Proposal. No relay, port, or firewall change is included in this track.

## Scope

Expose the HomeClaw stdio MCP server as a remotely reachable MCP endpoint for
Hermes on PiServ, using Supergateway and the private Tailnet path. The Mac
remains the HomeKit execution host, while PiServ remains the Hermes policy and
audit boundary.

This proposal does not require OpenClaw. Supergateway is only a transport
adapter between MCP stdio and Streamable HTTP.

## Architecture

```text
Hermes on PiServ
        |
        | authenticated MCP Streamable HTTP over Tailscale
        v
Supergateway on the Mac
        |
        | stdio
        v
HomeClaw MCP server
        |
        | Unix socket
        v
HomeClaw.app, started manually on macOS
        |
        v
Apple Home / HomeKit
```

Supergateway documents conversion from stdio MCP servers to Streamable HTTP,
including the `/mcp` endpoint and stateful sessions. See the
[Supergateway documentation](https://github.com/supercorp-ai/supergateway).

## Manual Startup

The operator starts the relay on the Mac after starting HomeClaw.app. The
relay owns the adapter child process so the stdio pipes remain connected:

```bash
npx -y supergateway \
  --stdio "node /Applications/HomeClaw.app/Contents/Resources/mcp-server.js" \
  --outputTransport streamableHttp \
  --stateful \
  --port 8765
```

The final command and port are implementation details to be pinned after a
local test. Starting a plain `mcp-server.js` in a separate terminal and then
trying to attach Supergateway later will not work: stdio is a process-local
transport.

## Network and Authentication

The relay must not be treated as authenticated merely because it is on the
Tailnet. Before exposing it to PiServ:

- bind or firewall the listener so only the Mac's Tailnet path is reachable;
- allow only the PiServ Tailnet identity in Tailscale ACLs;
- put an authenticated reverse proxy in front of the relay, or implement an
  equivalent verified bearer-token gate;
- use TLS if the selected transport leaves the trusted Tailnet boundary;
- apply MCP tool filtering so high-risk writes are unavailable by default;
- log tool calls and results without logging HomeKit secrets or private sensor
  payloads.

The relay command shown above is a transport example, not a complete security
configuration. Its authentication behavior must be verified before use.

## Implementation Phases

1. Confirm Node.js, Supergateway, HomeClaw.app, and the HomeClaw MCP adapter on
   the Mac.
2. Start the relay manually on loopback and verify MCP `initialize`, tool
   discovery, and a read-only HomeKit query.
3. Move the listener to a Tailnet-only path and add the selected authentication
   layer and Tailscale ACL.
4. Connect Hermes using the remote Streamable HTTP MCP endpoint with bounded
   request, session, and reconnect timeouts.
5. Enable approved writes only after read-only validation, with confirmation,
   audit, and post-write verification.

## Validation Gates

- PiServ can initialize the remote MCP session only through the Tailnet path.
- A non-Tailnet source cannot reach the relay.
- An unauthenticated request is rejected before MCP tool execution.
- HomeClaw.app closure, Mac sleep, relay exit, and HomeKit denial produce
  bounded gateway-unavailable errors.
- Read-only discovery returns consistent device and scene inventories.
- A reversible write requires confirmation, is audited, and is verified by a
  subsequent read.
- Scene or automation changes have a captured before-state and a tested
  recovery path.

## Rollback

Stop the manually started relay and remove its Hermes MCP configuration. Remove
the Tailnet ACL and reverse-proxy rule only after confirming no other service
uses the listener. HomeClaw.app and Apple Home pairings remain unchanged.

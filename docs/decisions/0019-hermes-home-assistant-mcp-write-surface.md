# 0019: Hermes Home Assistant MCP Write Surface

## Status

Accepted on 2026-08-06.

## Context

Hermes needs to query and maintain the Home Assistant instance on the local
network. The official Home Assistant MCP Server exposes the entities and
operations selected through Home Assistant's Assist exposure policy. PiServ
could add a second allowlist and operation gateway, but that would duplicate
Home Assistant policy and prevent the intended maintenance workflow from using
newly approved Home Assistant operations without a PiServ role change.

## Decision

Accept the broader set of Home Assistant MCP tools exposed by the configured
Home Assistant instance. Home Assistant is the authoritative boundary for the
entities and operations available to Hermes; PiServ does not add a second
Home Assistant operation allowlist or block write-capable MCP tools after the
operator enables the integration.

The accepted path is:

```text
Hermes Agent
    |
    | dedicated long-lived token, private on PiServ
    v
Home Assistant MCP Server
    |
    | Home Assistant Assist exposure policy
    v
Exposed entities and operations
```

This decision does not:

- enable Hermes' built-in `homeassistant` toolset;
- authorize terminal, filesystem, SSH, or arbitrary PiServ maintenance;
- permit credentials in Ansible variables, Git, prompts, or logs;
- bypass Home Assistant authentication or its Assist exposure policy.

The MCP server remains disabled by default. Enabling it requires an explicit
deployment variable and an operator-managed token file owned by `hermes-agent`.
The dashboard and inference provenance audit remain enabled according to the
consuming PiServ configuration.

## Consequences

- Newly exposed Home Assistant write operations become available to Hermes
  without a PiServ code change.
- The Home Assistant entity exposure policy becomes security-critical and must
  be reviewed before exposing an entity to Assist.
- A Home Assistant token compromise could permit every operation currently
  exposed by its MCP Server to be requested through Hermes.
- Future unattended-action restrictions require a new decision and must not be
  inferred from this acceptance.
- The existing reversible light operation remains the live acceptance proof;
  the Home Assistant instance remains responsible for the final entity and
  operation selection.

## Validation

On 2026-08-05, PiServ authenticated to the configured Home Assistant MCP
endpoint, discovered 21 tools, read the exposed upstairs stairs light state,
then invoked `HassTurnOn` and `HassTurnOff` in separate requests with a
controlled four-second interval. Home Assistant confirmed both operations and
the final state was `off`.

## References

- [Hermes Agent runbook](../runbooks/hermes-agent.md)
- [Hermes Agent framework research](../tracks/hermes-agent-framework-research.md)
- [Home Assistant MCP integration](https://www.home-assistant.io/integrations/mcp/)

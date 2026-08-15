# 0021: Hermes Agent Delegation over SSH Stdio MCP

## Status

Accepted on 2026-08-13.

## Context

PiServ runs Hermes Agent `0.20.0` from pinned upstream revision
`222465d84709379b65173b0283a6eea87516acfa`. MCP clients need one direct tool
that submits a task to this persistent agent identity and returns its result.

The installed upstream provides three adjacent surfaces:

| Surface | Capability | Fit |
| --- | --- | --- |
| `hermes mcp serve` | Messaging conversations, events, delivery, and approvals | No agent turn |
| `hermes acp` | Full agent session over ACP stdio | MCP clients cannot consume ACP |
| Hermes API server | Full agent turn over an OpenAI-compatible HTTP API | Requires a network listener or another protocol bridge |

The established non-interactive agent entry point is
`hermes chat --query PROMPT --quiet --source tool`. A narrow MCP adapter can
invoke it without reimplementing Hermes, its provider, or Home Assistant.

## Decision

Install a root-owned Python stdio MCP adapter with one tool:

```text
delegate_task(prompt)
```

The adapter starts one argv-based `hermes chat --query` subprocess as
`hermes-agent`. It inherits the managed Hermes home, Codex authentication,
memory, skills, and configured MCP integrations. The subprocess receives an
explicit CLI-only toolset override containing `delegation`, `file`, `memory`,
`session_search`, `skills`, `terminal`, `todo`, and every explicitly configured
MCP integration, currently `home-assistant-assist`. These are native tools in
the real Hermes agent loop: they are not represented as stateless callback
tools on the outer MCP adapter.

Hermes applies `agent.disabled_toolsets` after `--toolsets`, so the command-line
override alone cannot enable the required stateful tools. Ansible therefore
derives a delegation-only config from the authenticated managed config, removes
only the required native toolsets from its global deny-list, disables the
memory and skill write-approval staging gates, and omits dashboard credentials.
It replaces the Home Assistant MCP configuration with a fixed sudo-mediated
stdio broker. The delegation service receives no Home Assistant token
environment and an `InaccessiblePaths` bind hides the private token file. The
broker runs in a separate transient `DynamicUser` service, reads the token
there, and forwards bounded JSON-RPC only to the configured `/api/mcp` target.
The wrapper binds this artifact over `config.yaml` only inside the transient
delegation service, applies `MemoryMax` and `LimitAS` containment, and starts
Hermes with `--yolo`; the dashboard and conversations MCP retain their original
config and confirmation policy. The delegation layer adds no read-only or
confirmation boundary. Existing Hermes hardline guards, the systemd filesystem
sandbox, Home Assistant exposure, and Home Assistant credentials remain the
actual capability boundaries.

Keep transport identities separate:

```text
hermes-piserv                 hermes-delegate-piserv
       |                               |
codex-hermes-mcp              codex-hermes-delegate
       |                               |
hermes mcp serve              bounded delegate_task adapter
```

Both accounts are password-locked and forced-command-only. Each has one exact
no-argument sudo rule for its root-owned wrapper. The wrapper launches a
transient systemd service as `hermes-agent`, reusing the conversations MCP
sandbox, delegation-only read-only config bind, read-only policy bind, private
temporary directory, and Home Assistant environment-file boundary while
preserving MCP stdio. Neither endpoint permits a shell, SSH forwarding, a PTY,
arbitrary remote commands, general sudo, or a network listener.

The adapter accepts a non-empty UTF-8 prompt up to 32 KiB, permits one active
turn, limits Hermes to 50 tool turns and 300 seconds, bounds stdout and stderr
to 1 MiB each, and sends both SIGTERM and SIGKILL to the process group on
timeout or overflow, including when the leader exits first. Prompt text is one
subprocess argv value and never enters a shell. Child stderr is not returned,
preventing accidental credential disclosure; failures become MCP tool errors
with only bounded status information.

## Consequences

- MCP clients can delegate one complete task while retaining Hermes state and
  enabled integrations.
- The task prompt is visible transiently in the PiServ process argument list
  while Hermes runs because the upstream CLI accepts `--query` as an argument.
- The 300-second synchronous contract is suitable for direct delegation, not
  long-lived background jobs.
- The existing messaging MCP remains compatible and independently revocable.
- Upstream ACP is preferable for a future ACP-native client that needs streamed
  tool activity or interactive approvals.

## Validation

Source validation renders both SSH wrappers, the credential broker, and the
adapter; runs ShellCheck; compiles the rendered Python; and exercises literal
prompt handling, failure redaction, child-process cleanup, broker forwarding,
oversized frames, fresh check mode, and output bounds. The playbook verifies
the effective sandboxed Hermes tool catalog after every convergence. Live
acceptance must additionally prove exact SSH/sudo policy, MCP discovery, a
harmless Home Assistant read, and the runbook's target-specific matrix before
an authorized write.

## References

- [Hermes messaging MCP source at the pinned revision](https://github.com/NousResearch/hermes-agent/blob/222465d84709379b65173b0283a6eea87516acfa/mcp_serve.py)
- [Hermes ACP documentation at the pinned revision](https://github.com/NousResearch/hermes-agent/blob/222465d84709379b65173b0283a6eea87516acfa/website/docs/user-guide/features/acp.md)
- [Hermes API server documentation at the pinned revision](https://github.com/NousResearch/hermes-agent/blob/222465d84709379b65173b0283a6eea87516acfa/website/docs/user-guide/features/api-server.md)
- [Hermes CLI toolset filtering at the pinned revision](https://github.com/NousResearch/hermes-agent/blob/222465d84709379b65173b0283a6eea87516acfa/model_tools.py#L434-L471)
- [Hermes toolset reference at the pinned revision](https://github.com/NousResearch/hermes-agent/blob/222465d84709379b65173b0283a6eea87516acfa/website/docs/reference/toolsets-reference.md)
- [Hermes Home Assistant MCP write decision](0019-hermes-home-assistant-mcp-write-surface.md)
- [Hermes delegation MCP runbook](../runbooks/hermes-delegation-mcp-ssh.md)

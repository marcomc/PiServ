# Hermes Agent Framework Research

## Table of Contents

- [Result](#result)
- [Evidence](#evidence)
- [Selected Architecture](#selected-architecture)
- [Recommended Architecture](#recommended-architecture)
- [Home Assistant and Apple Home Roadmap](#home-assistant-and-apple-home-roadmap)
- [Codex CLI Boundary](#codex-cli-boundary)
- [Cloud Corpus Design](#cloud-corpus-design)
- [Implementation Gates](#implementation-gates)
- [Sources](#sources)

## Result

PiServ can run **Nous Hermes Agent** as its persistent, unprivileged control
plane. The framework's memory, user profile, sessions, skills, provider
configuration, and capability policy are service data held on PiServ; they are
not model weights. Direct Hermes Chat is this service's browser interface.

PiServ cannot be assumed to host a compatible local inference model: Hermes
requires a 64K context window for its agentic workflow, which excludes the
compact 32K models that are plausible candidates for PiServ's 4 GB memory
budget. This does not prevent Hermes itself from running on PiServ while the
model provider runs elsewhere.

The recommended first deployment is therefore **Nous Hermes Agent on PiServ
with Codex authenticated through ChatGPT Pro as its provider**. It gives the
agent a durable learning location now and makes a future switch to a stronger
local, OpenAI-compatible model endpoint a provider configuration change rather
than a migration. PiServ must still pass a process-memory benchmark and its
terminal and filesystem tools must remain isolated.

| Component | Role | Decision |
| --- | --- | --- |
| Nous Hermes Agent + Codex | PiServ's persistent control plane and first provider | Validate as a sandboxed integration |
| Custom 64K local endpoint | Future Mac or dedicated inference-host provider | Switch only after model and tool benchmarks |

## Evidence

The following observations are current as of 2026-07-30:

| Area | Evidence | Implication |
| --- | --- | --- |
| PiServ | The recorded 2026-07-08 baseline is Debian 13 `trixie`, `arm64`, with 4.0 GiB RAM and 2.0 GiB zram. | There is no realistic headroom for a general 3B+ model beside existing services. |
| Hermes local models | Hermes documents a 64K minimum context for agentic use. | Its standard local profile is incompatible with the compact 32K starting models under consideration. |
| Hermes learning | Hermes persists curated memory and skills independently of its provider selection. | Retain Hermes service data on PiServ while switching backends. |
| Hermes providers | Hermes supports OpenAI Codex, custom OpenAI-compatible endpoints, and configured fallbacks. | Codex can be the initial provider and a future LAN model can replace it. |

## Selected Architecture

### 1. Nous Hermes Agent: persistent control plane

Hermes is the correct framework for the stated objective: it can retain
curated memory and reusable skills on PiServ while the selected model provider
changes. Its provider runtime covers the CLI, gateway, cron jobs, and auxiliary
model calls; it supports OpenAI Codex and saved custom OpenAI-compatible
endpoints. It also supports a fallback-provider chain.

The first provider can be Codex authenticated by ChatGPT Pro. Later, point the
same Hermes installation at a 64K-capable model hosted on the Mac or a
dedicated machine. The persistent memory, user profile, skills, sessions, and
audit trail stay on PiServ as long as the managed Hermes data directory is
preserved and backed up.

This is not model training. Hermes' self-learning loop records facts and
procedures; model quality affects what it proposes, so new or changed skills
must be versioned, auditable, and reversible. Do not allow an automatic skill
to bypass the capability gateway.

The initial service still needs these constraints:

- Run under a dedicated unprivileged account with a private, backed-up service
  data directory.
- Start with no generic terminal, filesystem, browser, code execution, or SSH
  toolset. Expose only the shared capability gateway.
- Use the Codex provider rather than enabling the optional Codex App-Server
  shell and patch toolset. Reconsider the App-Server only in an isolated
  sandbox when a capability requires it.
- Use a per-request confirmation before Cloud Corpus or Home Assistant state
  is sent to Codex.

## Recommended Architecture

```text
Direct Hermes Chat (product interface)
        |
        v
Nous Hermes Agent on PiServ (unprivileged)
        |
        +-- persistent service data --> memory, skills, sessions, audit,
        |                              capability policy
        |
        +-- initial provider --> Codex (ChatGPT Pro authentication)
        |
        +-- shared capability gateway --> Cloud Corpus read tools
        |                                Home Assistant MCP / Assist API
        |                                approved maintenance operations
        |
        +-- later provider --> Mac or future LAN 64K local-model endpoint
```

The capability gateway is the durable security boundary. The model may select a
tool, but it cannot enlarge the tool's authority. Each tool must have a typed
input schema, target allowlist, timeout, result normalization, audit record,
and an explicit read-only or write-capable classification.

Model specialization must also stay outside the model weights at first. Hermes
uses its persistent memory and skills for learned facts and procedures, while
the capability gateway supplies bounded Cloud Corpus retrieval, tool
descriptions, examples, and audit-derived policies. This makes a future local
provider personal without trying to fine-tune it. A provider change preserves
these assets but not the previous model's exact reasoning behavior, so every
approved tool and skill must be revalidated after the change.

Initial tools should be limited to:

- Cloud-file metadata search and bounded content reads.
- PiServ service and storage status.
- Home Assistant state queries through the Assist API.
- An escalation-request tool that produces a reviewable package but does not
  invoke Codex before the user confirms the external data disclosure.

Approved Operations can be added without redesigning the agent. Each one becomes
another gateway capability, first requiring confirmation and later eligible for
an Autonomous Operation policy after a live test and audit review.

## Home Assistant and Apple Home Roadmap

### Phase 1: Home Assistant context

Use Home Assistant's official MCP Server integration and the built-in Assist
API instead of giving the PiServ agent a broad REST token. Home Assistant
documents the Assist API as equivalent to the exposed entities available to the
built-in conversation agent and states that it cannot perform administrative
tasks. The MCP endpoint is `/api/mcp/assist`.

This provides a natural per-entity boundary through Home Assistant's exposed
entities configuration. Start with state-only queries; add tightly scoped
service calls only after testing them through the same gateway.

### Phase 2: Home Assistant Assist channel

Home Assistant supports custom `ConversationEntity` implementations. A small
Home Assistant integration can forward Assist text and conversation IDs to the
PiServ Agent Service, then return the response to the existing Assist pipeline.
This is the correct bridge for the planned Home Assistant Assist Channel; it is
not necessary for the initial private browser chat.

### Phase 3: Apple Home and Siri

Keep device control in Home Assistant. The official HomeKit Bridge exposes
selected Home Assistant entities to Apple Home, where Siri can control them.
This gives Hermes an indirect path: it changes an allowed Home Assistant state,
and HomeKit reflects that state to Apple Home.

HomeKit Bridge is not a documented general conversation bridge to an external
agent. A future arbitrary Siri-to-agent fallback requires a signed iOS/iPadOS
or macOS app that publishes a small set of App Intents/App Shortcuts, or a
user-managed Shortcut that calls a protected PiServ endpoint. Apple documents
App Intents as the supported route for actions exposed to Siri and Shortcuts.
Treat that as a separate client project after the first two phases are stable.

## Codex CLI Boundary

The requested subscription path is a supported provider route, subject to the
normal ChatGPT plan terms and limits.
OpenAI documents that Codex is included with ChatGPT Pro, works through the CLI
after ChatGPT sign-in, and can be controlled programmatically through the
Codex SDK. Hermes documents an optional Codex App-Server runtime that uses
ChatGPT subscription authentication rather than an API key.

The direct integration is therefore technically viable. The individual Terms
of Use still apply, including their restriction on automatically or
programmatically extracting Output. The implementation must use the supported
Codex integration path, retain normal plan usage limits, and never share the
operator's account credentials.

The initial policy is an in-chat confirmed handoff:

1. PiServ prepares a redacted, bounded escalation package.
2. Direct Hermes Chat identifies the destination as Codex and asks the
   operator to approve the external disclosure for that request.
3. After approval, Hermes invokes Codex directly and returns the
   normalized result to the same conversation.

Background or policy-based Codex escalation remains deferred until the audit
trail supports a separate approval decision.

## Cloud Corpus Design

The Cloud Corpus is authorized to cover the whole pCloud and Google Drive
accounts, but that does not require indexing every byte on PiServ. With 4 GB
RAM, begin with a durable metadata index and request-time, bounded extraction:

- pCloud: consume the existing full-account FUSE mount at `/mnt/pcloud` through
  a read-only tool identity. Do not expose the raw mount to an agent process.
- Google Drive: use the planned `rclone` remote and its least-privilege OAuth
  configuration; do not treat an OAuth token as an agent credential.
- Retrieval: allow metadata search, document previews, MIME-validated text
  extraction, size limits, and source citations. Reject executable files,
  secrets paths, and unbounded directory walks by default.
- Indexing: defer embeddings and whole-account vector indexing until measured
  disk, RAM, privacy, and stale-content behavior justify them.

The existing pCloud and Google Drive tracks remain the source of truth for
mount, OAuth, storage, backup, and restore decisions.

## Implementation Gates

No component should be installed until these gates pass on PiServ:

1. **Hermes runtime:** benchmark an unprivileged Hermes service on PiServ with
   no local model loaded. Record RSS, swap, response latency, restart recovery,
   and permissions on its persistent service data.
2. **Learning persistence:** prove that a curated memory entry and a reviewed
   skill survive a Hermes restart and a provider change. Back up and restore the
   service data, then verify audit continuity and rollback of a changed skill.
3. **Codex:** prove Linux `arm64` CLI installation, subscription login,
   per-request disclosure confirmation, sandbox isolation, result redaction,
   audit capture, and graceful handling of plan usage limits. Historical
   Raspberry Pi ARM64 crash reports make a live smoke test mandatory.
4. **Provider migration:** configure a test custom OpenAI-compatible endpoint,
   switch Hermes from Codex to it, and rerun a fixed suite of conversations and
   read-only tools. The future model must offer at least 64K context.
5. **Gateway policy:** prove path traversal, unsupported MIME types, oversized
   reads, unapproved operation IDs, and malformed Home Assistant targets fail
   closed and are audited.
6. **Home Assistant:** expose a small entity set, verify MCP authentication and
   state reads, then test one reversible service call with a confirmation.
7. **Cloud Corpus:** validate pCloud and Google Drive retrieval against known
   documents without leaking credentials into prompts or logs.
8. **Network and identity:** bind Direct Hermes Chat only to the LAN/Tailnet
   policy and authenticate it with the initial PiServ administrator identity.

After the gates pass, codify the selected service, capability gateway,
credentials, firewall policy, health checks, and runbook in Ansible.

## Sources

- [Hermes Agent quickstart and model requirements](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/quickstart.md)
- [Hermes Agent persistent memory](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md)
- [Hermes Agent provider runtime and fallbacks](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/provider-runtime.md)
- [Hermes Agent Home Assistant integration](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/homeassistant.md)
- [Hermes Agent Codex App-Server runtime](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/codex-app-server-runtime.md)
- [Hermes Agent security guidance](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md)
- [Home Assistant MCP integration](https://www.home-assistant.io/integrations/mcp/)
- [Home Assistant LLM and Assist API](https://developers.home-assistant.io/docs/core/llm/)
- [Home Assistant conversation entity API](https://developers.home-assistant.io/docs/core/entity/conversation/)
- [Home Assistant HomeKit Bridge](https://www.home-assistant.io/integrations/homekit/)
- [Apple App Intents documentation](https://developer.apple.com/documentation/appintents)
- [OpenAI: using Codex with a ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-chatgpt)
- [OpenAI: Codex CLI and Sign in with ChatGPT](https://help.openai.com/en/articles/11381614-api-codex-cli-and-sign-in-with-chatgpt)
- [OpenAI: individual Terms of Use](https://openai.com/policies/terms-of-use/)
- [OpenAI Codex CLI Linux ARM64 package](https://www.npmjs.com/package/%40openai/codex)
- [Existing PiServ system baseline](../runbooks/system-baseline-inventory.md)
- [Existing PiServ Google Drive and storage track](google-drive-and-external-storage.md)
- [Existing PiServ pCloud storage track](pcloudcc-podcast-storage.md)

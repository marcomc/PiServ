# Hermes Agent Framework Research

## Table of Contents

- [Result](#result)
- [Evidence](#evidence)
- [Implementation Status](#implementation-status)
- [Selected Architecture](#selected-architecture)
- [Recommended Architecture](#recommended-architecture)
- [Home Assistant and Apple Home Roadmap](#home-assistant-and-apple-home-roadmap)
- [Codex CLI Routing](#codex-cli-routing)
- [Cloud Corpus Design](#cloud-corpus-design)
- [Implementation Gates](#implementation-gates)
- [Sources](#sources)

## Result

PiServ can run **Nous Hermes Agent** as its persistent, unprivileged control
plane. The framework's memory, user profile, sessions, skills, provider
configuration, and capability policy are service data held on PiServ; they are
not model weights. Direct Hermes Chat is this service's browser interface.

PiServ cannot safely host a suitable 64K local inference provider with its
current 4 GB RAM. Hermes requires a 64K context window for its agentic
workflow, which excludes compact 32K models. The live cgroup v2 memory
controller contained guarded full-provider tests, but Gemma 4 E2B and Granite
3.3 2B crossed the 1.5 GiB host-reserve threshold. A Llama 3.2 1B synthetic
test passed, but its complete Hermes proof ended in an unclean host stop while
processing the Hermes prompt. This does not prevent Hermes itself from running
on PiServ while the model provider runs elsewhere.

The recommended first deployment is therefore **Nous Hermes Agent on PiServ
with Codex authenticated through ChatGPT Pro as its provider**. It gives the
agent a durable learning location now and makes a future switch to a stronger
local, OpenAI-compatible model endpoint a provider configuration change rather
than a migration. PiServ must still pass a process-memory benchmark and its
terminal and filesystem tools must remain isolated.

| Component | Role | Decision |
| --- | --- | --- |
| Nous Hermes Agent + Codex | PiServ's persistent control plane and first provider | Validate as a sandboxed integration |
| Gemma 4 E2B mobile text-only endpoint | Future 8 GB host candidate | Retain framework; not installed on current 4 GB host |
| Granite 3.3 2B Instruct endpoint | Future 8 GB host candidate | Retain framework; not installed on current 4 GB host |
| Llama 3.2 1B Instruct endpoint | Future 8 GB host candidate | Synthetic 64K loopback test passed; full Hermes proof caused an unclean host stop on 4 GB |
| Custom 64K local endpoint | Future Mac or dedicated inference-host provider | Switch only after model and tool benchmarks |

## Evidence

The following observations are current as of 2026-08-05:

| Area | Evidence | Implication |
| --- | --- | --- |
| PiServ | The recorded 2026-07-08 baseline is Debian 13 `trixie`, `arm64`, with 4.0 GiB RAM and 2.0 GiB zram. | There is no realistic headroom for a general 3B+ model beside existing services. |
| Hermes local models | `memory` is active in cgroup v2 and model services had enforced `MemoryHigh`, `MemoryMax`, and `MemorySwapMax` values. Guarded 64K provider proofs crossed the 1.5 GiB host reserve for both Gemma and Granite while the dashboard stayed healthy. | Neither model is viable as a 64K Hermes provider on the 4 GB host; remove their deployed artifacts and retain the framework for an 8 GB upgrade. |
| Local alternatives | Llama 3.2 1B has 128K native context. Its Q4_K_M artifact passed a guarded synthetic 64K loopback test at about 1.50 GiB cgroup memory, but a full Hermes proof became unreachable at 47% of a 2,038-token prompt and the next boot confirmed an unclean stop. | It is not a safe default provider on the 4 GB host; retain the framework for an 8 GB upgrade. |
| Hermes learning | Hermes persists curated memory and skills independently of its provider selection. | Retain Hermes service data on PiServ while switching backends. |
| Hermes providers | Hermes supports OpenAI Codex, custom OpenAI-compatible endpoints, and configured fallbacks. | Codex can be the initial provider and a future LAN model can replace it. |

## Implementation Status

The runtime and authenticated provider flow were validated live on 2026-07-31:

- Hermes `0.20.0` is pinned to upstream release commit
  `3c27eb6234bf91b8ceee9e9071591b31e9b148cb` (`v2026.8.3`).
- The service runs as the unprivileged `hermes-agent` identity with private
  state under `/var/lib/hermes-agent`.
- Codex CLI `0.145.0` was installed from the official Linux ARM64 release
  archive after SHA-256 verification and passed its version smoke test.
- ChatGPT device authorization completed separately for Codex CLI and Hermes.
  Hermes returned a minimal `openai-codex` response in 10 seconds; direct Codex
  CLI returned an equivalent read-only response in 22 seconds without an API
  key.
- The Hermes CLI policy exposes only memory and skills. Both write paths
  require review; terminal, file, browser, code execution, and Home Assistant
  are explicitly disabled.
- The browser dashboard is active only on `127.0.0.1:9119` and returned HTTP
  `200`. Operator access uses an SSH tunnel. Its post-convergence idle process
  used about 135 MiB RSS while the host retained about 2.7 GiB available
  memory. A forced process failure recovered to HTTP `200` in 13 seconds.
- A daily systemd timer creates full state archives in the private
  `/mnt/external-data/backups/hermes-agent` directory. The first live backup
  completed successfully.
- The deployment is codified in `ansible/roles/hermes_agent` and
  `ansible/playbooks/hermes-agent.yml`.
- The retained llama.cpp framework is loopback-only. Gemma 4 E2B and Granite
  3.3 2B were removed from the current 4 GB host after guarded 64K proofs
  crossed the reserve threshold. Neither is enabled as a Hermes provider.
- Llama 3.2 1B Instruct passed the synthetic 64K loopback check but failed the
  isolated full Hermes proof when PiServ became unreachable during prompt
  processing. Its temporary deployment was removed and Codex remains the only
  provider on the current hardware.

On 2026-08-05, a reproducible audit of the deployed `v2026.8.3` lockfile found
one moderate transitive production vulnerability in `undici` below `6.28.0`.
Upstream `main` has already advanced to `undici` `7.28.0`, but no newer release
tag is available to pin. The dashboard serves prebuilt assets through a
Python service; it does not execute Node or npm in production.
The dashboard now uses Hermes native password authentication with a
source-scoped LAN UFW rule and existing Tailnet ingress policy. Keep direct LAN
access on a trusted network until a separate TLS reverse-proxy deployment is
approved.

## Selected Architecture

### 1. Nous Hermes Agent: persistent control plane

Hermes is the correct framework for the stated objective: it can retain
curated memory and reusable skills on PiServ while the selected model provider
changes. Its provider runtime covers the CLI, gateway, cron jobs, and auxiliary
model calls; it supports OpenAI Codex and saved custom OpenAI-compatible
endpoints. It also supports a fallback-provider chain.

The first provider can be Codex authenticated by ChatGPT Pro. Later, point the
same Hermes installation at either local candidate endpoint on PiServ only after
a provider-migration test, or at a model hosted on the Mac or a dedicated
machine. The persistent memory, user profile, skills, sessions, and audit trail
stay on PiServ as long as the managed Hermes data directory is preserved and
backed up.

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
- Route eligible requests and non-text attachments to Codex without a
  per-request confirmation. Return a compact provenance notice and retain an
  audit record without request or response contents.

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
        +-- future local providers --> Gemma 4 E2B or Granite 3.3 2B on an
        |                              8 GB-or-larger PiServ after guarded proofs
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
- A route-selection capability that sends eligible requests to Codex under the
  pre-authorized policy and returns the selected-provider provenance.

Approved Operations can be added without redesigning the agent. Each one becomes
another gateway capability, first requiring confirmation and later eligible for
an Autonomous Operation policy after a live test and audit review.

## Home Assistant and Apple Home Roadmap

### Phase 1: Home Assistant context

Use Home Assistant's official MCP Server integration and the built-in Assist
API instead of giving the PiServ agent a broad REST token. Home Assistant
documents the Assist API as equivalent to the exposed entities available to the
built-in conversation agent and states that it cannot perform administrative
tasks. The MCP Server integration endpoint is `/api/mcp`.

This provides a natural per-entity boundary through Home Assistant's exposed
entities configuration. On 2026-08-05, an authenticated Hermes chat completed
a state read and a reversible four-second upstairs-stairs light on/off test
through the gateway. Home Assistant confirmed both actions and the final state
was `off`.

Decision 0019 accepts the broader MCP write surface: Home Assistant's Assist
exposure policy is the authoritative entity and operation boundary, and PiServ
does not add a duplicate MCP operation allowlist.

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

## Codex CLI Routing

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

The initial policy is pre-authorized routing:

1. PiServ prepares a redacted, bounded escalation package.
2. Hermes routes an eligible request, attachment, or modality to Codex without
   a per-request confirmation.
3. The normalized result returns to the same conversation with a compact note
   that Codex analyzed the relevant context. This note must not block text,
   audio, or structured results.
4. The audit record retains the provider, route reason, data classification,
   timestamp, request ID, and outcome, but never raw request or response
   contents.

This authorization changes only the selected inference provider. It does not
authorize an Approved Operation, enable a disabled toolset, or bypass a
write-operation policy.

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

The runtime installation, ARM64 binary smoke test, authenticated provider
response, loopback dashboard, toolset allowlist, first backup, and content-free
Codex provenance audit are complete. The remaining gates are:

1. **Learning persistence:** prove that a curated memory entry and a reviewed
   skill survive a Hermes restart and a provider change. Back up and restore the
   service data, then verify audit continuity and rollback of a changed skill.
2. **Codex:** test modality-aware routing and graceful handling of plan usage
   limits.
3. **Provider migration:** configure a test custom OpenAI-compatible endpoint,
   switch Hermes from Codex to it, and rerun a fixed suite of conversations and
   read-only tools. The future model must offer at least 64K context.
4. **Gateway policy:** prove path traversal, unsupported MIME types, oversized
   reads, unapproved operation IDs, and malformed Home Assistant targets fail
   closed and are audited.
5. **Home Assistant:** retain the authenticated MCP gateway and its Assist
   per-entity exposure boundary. An end-to-end Hermes state read and reversible
   service-call proof has passed; define any future unattended-action policy
   separately.
6. **Cloud Corpus:** validate pCloud and Google Drive retrieval against known
   documents without leaking credentials into prompts or logs.
7. **Network and identity:** retain loopback plus SSH tunneling until an
   authenticated LAN/Tailnet policy is implemented and tested.

After the gates pass, codify the capability gateway, credential references,
firewall policy, and authenticated health checks in Ansible.

## Sources

- [Hermes Agent quickstart and model requirements](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/quickstart.md)
- [Hermes Agent persistent memory](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/memory.md)
- [Hermes Agent provider runtime and fallbacks](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/developer-guide/provider-runtime.md)
- [Hermes Agent vision](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/vision.md)
- [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4)
- [IBM Granite 3.3 2B Instruct model card](https://huggingface.co/ibm-granite/granite-3.3-2b-instruct)
- [Llama 3.2 1B Instruct model card](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)
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

# PiServ Context

PiServ is a reproducible Raspberry Pi server. This context records the
project-specific language that governs its managed services and automation.

## Hermes Integration

**Hermes Agent**:
The Nous Hermes Agent deployment on PiServ that reasons over permitted PiServ,
cloud-storage, and home-automation information.
_Avoid_: generic chatbot, separate local agent

**Hermes Learning Store**:
The PiServ-resident persistent memory, user profile, skills, sessions, and
audit data that Hermes retains independently of its selected model provider.
_Avoid_: model weights, disposable chat history

**Initial Codex Provider**:
The Codex provider authenticated through the operator's ChatGPT Pro account,
used by Hermes until a suitable local provider is available.
_Avoid_: OpenAI API key, permanent cloud-only architecture

**Observation Mode**:
The Hermes operating mode that can retrieve and analyze permitted information
but cannot change external state.
_Avoid_: read-only prototype, reporting-only mode

**Approved Operation**:
A write-capable action with an explicit capability, target boundary, validation
rule, and audit trail. It can be enabled after separate live testing.
_Avoid_: unrestricted write access, arbitrary command execution

**Autonomous Operation**:
An Approved Operation that Hermes may invoke without a per-request human
confirmation under a documented policy.
_Avoid_: background write access, full control

**SSH Operation**:
An Approved Operation that accesses a named remote target through a dedicated
identity and an explicit remote-command policy. It is introduced only after
the lower-risk operation paths are live-tested.
_Avoid_: interactive shell access, shared administrator login

**Cloud Corpus**:
The planned complete pCloud and Google Drive account content that Hermes may
retrieve and analyze for the operator after its separate retrieval gateways are
implemented and validated.
_Avoid_: selected-folder source, public knowledge base

**Pre-authorized Codex Routing**:
The automatic routing of an eligible Hermes request or non-text attachment to
the operator-authorized Codex provider. It does not wait for a per-request
confirmation.
_Avoid_: per-request disclosure gate, unrecorded provider fallback

**Inference Provenance Notice**:
The compact response note and structured response metadata that state when
Codex analyzed a request or attachment.
_Avoid_: blocking notification, undisclosed provider use

**Preferred LAN Inference**:
The future 64K-capable local model hosted on a reachable LAN machine, initially
the operator's Mac and later a dedicated inference host if one is added.
_Avoid_: PiServ-resident model, required first-release dependency

**Direct Hermes Chat**:
The private browser interface served by PiServ for direct operator conversations
with Hermes.
_Avoid_: Home Assistant Assist channel, public chat service

**Home Assistant Assist Channel**:
The planned Home Assistant conversation path that will supply an operator
request to Hermes and return its response to Assist after separate validation.
_Avoid_: direct Hermes chat, generic Home Assistant automation

**Interaction Roadmap**:
The staged introduction of Direct Hermes Chat first, the Home Assistant Assist
Channel second, and both interfaces together after separate validation.
_Avoid_: simultaneous first release, Home Assistant-only design

**Authentication Roadmap**:
Direct Hermes Chat uses native dashboard password authentication. Do not reuse
the PiServ administrator identity for the dashboard.
_Avoid_: shared administrator login, unauthenticated LAN access

**Hermes Access Boundary**:
The LAN and authenticated Tailnet devices permitted to reach Direct Hermes Chat
in its initial release.
_Avoid_: public internet exposure, LAN-only access

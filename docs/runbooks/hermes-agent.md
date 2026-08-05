# Hermes Agent

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Planned Inference Routing](#planned-inference-routing)
- [Model Selection and Escalation](#model-selection-and-escalation)
- [Home Assistant Capability Gateway](#home-assistant-capability-gateway)
- [Local Model Benchmarks](#local-model-benchmarks)
- [Verify Persistence](#verify-persistence)
- [Deploy](#deploy)
- [Complete ChatGPT Login](#complete-chatgpt-login)
- [Open the Private Dashboard](#open-the-private-dashboard)
- [Validate](#validate)
- [Backup and Restore](#backup-and-restore)
- [Recovery](#recovery)

## Purpose

Operate the PiServ-resident Nous Hermes Agent with Codex authenticated through
the operator's ChatGPT subscription. Hermes owns persistent memory, skills,
sessions, and audit data; Codex is the initial inference provider.

## Current State

Live state observed on 2026-07-31:

| Item | State |
| --- | --- |
| Hermes | `0.19.0`, upstream commit `240afd0b70a016ba17568d597e0f2c32f94f4cfd` |
| Runtime identity | `hermes-agent`, system account with no login shell |
| Persistent data | `/var/lib/hermes-agent`, mode `0700` |
| Codex CLI | `0.145.0`, official ARM64 archive with SHA-256 verification |
| Provider | `openai-codex`, authenticated through ChatGPT device authorization |
| Enabled toolsets | `memory`, `skills` |
| Write gates | Memory and skill writes require approval |
| Disabled toolsets | Terminal, file, browser, code execution, Home Assistant, and all other bundled toolsets |
| Dashboard | `127.0.0.1:9119`, reachable only locally or through an SSH tunnel |
| Backups | Daily full archive on `/mnt/external-data/backups/hermes-agent` |

The first live dashboard probe returned HTTP `200`. The first backup contained
2,749 files, compressed 218.6 MB to 72.3 MB, and completed in 11 seconds.
After the Ansible convergence restart, the idle dashboard process used about
135 MiB RSS; the host retained about 2.7 GiB available memory.
A forced process failure restarted automatically and returned HTTP `200` with a
new PID after 13 seconds.
On 2026-07-31, Hermes returned a minimal authenticated `openai-codex` response
in 10 seconds. The direct Codex CLI returned an equivalent read-only response
in 22 seconds without an API key.

The pinned upstream revision contains a tracked, process-specific
`.lazy-refresh-incomplete` marker. The role removes it after installation so
the unprivileged runtime does not attempt package repair on every command.

## Planned Inference Routing

Codex is an operator-pre-authorized inference provider. When route selection
and non-text handling are enabled, Hermes may send an eligible request or
attachment to Codex without a per-request confirmation. Each response must
include a compact provider-provenance note when Codex analyzed its context;
the note must not block text, audio, or structured results.

The corresponding audit record must contain the provider, route reason, data
classification, timestamp, request ID, and outcome without persisting request
or response contents. Provider routing does not authorize a write operation or
enable any currently disabled toolset.

The current deployment uses ordered provider-failure fallback, not
task-complexity routing, and keeps the vision toolset disabled.

## Model Selection and Escalation

The Ansible deployment configures `gpt-5.6-luna` as the default model and uses
`gpt-5.3-codex-spark`, `gpt-5.6-terra`, then `gpt-5.6-sol`, only after a Luna
provider failure (for example, rate limit, overload, connection failure, or
authentication failure). This failure fallback does not classify task
complexity. Spark is text-only and uses its separate ChatGPT Pro preview
allowance; an image request must continue to a vision-capable fallback.

The default effort is `medium`. Model-specific overrides set Spark to `low`,
Terra to `high`, and Sol to `xhigh`. `max` and `ultra` are not configured:
they are explicit operator choices, and Ultra is inconsistent with the current
disabled `delegation` toolset.

For a deliberately more capable one-turn response in an interactive Hermes
session, select one of these configured aliases:

```text
/model terra
/model sol
```

These changes apply only to the current session. Use `--global` only for a
deliberate persistent default change. Start a new session to return to Luna.
Do not enable `smart_model_routing`: its task-complexity policy is not verified
for this Hermes release.

Every completed model response carries a compact provider/model note. The
managed provenance plugin also appends one private JSONL audit record containing
only timestamp, event ID, session ID, provider, model, route reason, data
classification, platform, and outcome. It does not store prompt or response
content.

## Home Assistant Capability Gateway

The managed integration is intentionally disabled until its three external
inputs are available: the Home Assistant base URL, an access token, and a
small initial set of entities exposed only for state queries. It connects Hermes
to Home Assistant's official MCP endpoint at `/api/mcp`; it does not enable
Hermes' broader built-in `homeassistant` toolset.

Home Assistant controls which entities and operations its MCP server exposes.
PiServ does not add a second write restriction, so approved Home Assistant MCP
tools can perform available actions through the same audited Hermes runtime.

On Home Assistant, first enable the **MCP Server** integration and expose only
read-only entities for the initial test. Create a dedicated long-lived access
token. On PiServ, store it without printing it:

```sh
sudo install -o hermes-agent -g hermes-agent -m 0600 /dev/null \
  /var/lib/hermes-agent/home-assistant-mcp.env
sudoedit /var/lib/hermes-agent/home-assistant-mcp.env
```

The file must contain exactly one assignment:

```text
HASS_MCP_TOKEN=<long-lived-access-token>
```

Then set `hermes_agent_manage_home_assistant_mcp: true` and the full endpoint
URL in the PiServ playbook, apply it, and prove authentication plus a state
query. Do not add controllable entities or service-call policies until that
read-only proof and its audit trail have been reviewed.

## Local Model Benchmarks

The Hermes deployment also manages a loopback-only `llama.cpp` benchmark
runtime. It stores checksum-pinned model files outside Hermes state, on the
filesystem containing `/var/lib/hermes-models`, and the benchmark starts exactly one service
before stopping it on completion. No local model is configured as the Hermes
provider until it passes the benchmark and a separate provider-migration test.

| Model ID | Model | Context | Purpose |
| --- | --- | ---: | --- |
| `gemma-4-e2b` | Gemma 4 E2B text-only Q4_0 | 64K configured | Primary PiServ candidate |
| `granite-3-3-2b` | Granite 3.3 2B Instruct Q4_K_M | 64K configured | Direct open-license comparison |
| `llama-3.2-1b-instruct` | Llama 3.2 1B Instruct Q4_K_M | 64K configured | Lightweight comparison |

### Current 4 GB Host Result

The live cgroup v2 memory controller is active. Guarded 64K full-provider
tests stopped Gemma 4 E2B and Granite 3.3 2B after each crossed PiServ's
1.5 GiB host-reserve threshold. The guards stopped only the relevant model
service and the dashboard remained reachable with HTTP `200`, but neither
model has sufficient headroom for a safe 64K Hermes provider on this 4 GB
host. Their GGUF files and systemd units have been removed from PiServ.

The reusable benchmark and deployment framework remains in the repository but
`hermes_agent_manage_local_models` is disabled in the PiServ playbook. Re-enable
it only on a host with at least 8 GB RAM, then repeat the guarded full-provider
proof before selecting either model. Codex remains the current provider.

On 2026-08-04, a Q4_K_M Llama 3.2 1B artifact generated locally from Meta's approved official source revision
`9213176726f574b556790deb65791e0c5aa438b6` passed a loopback-only 64K synthetic
response test. Its SHA-256 is
`257a0a37301cd78f6dab4ed2a65d0ace8e1d0fc43d4f1070b0cf595a0426208f`; it returned
`HERMES_LOCAL_MODEL_OK` in 1.2 seconds with about 1.50 GiB cgroup memory, no
cgroup memory events, and dashboard HTTP `200`. The test service was stopped
afterwards.

The subsequent isolated full-provider proof cloned Hermes state, loaded a
read-only skill and memory marker, and used a loopback-only Llama service with
`MemoryHigh=2 GiB`, `MemoryMax=2500 MiB`, and `MemorySwapMax=512 MiB`. While
processing the 2,038-token Hermes prompt, the model reached 47% prompt progress;
the Pi then became unreachable and the next boot reported unclean journal and
filesystem recovery. No OOM, cgroup `memory.events`, thermal, undervoltage, or
kernel-panic record survived before the interruption. The evidence is therefore
insufficient to assign a physical cause, but sufficient to reject Llama as a
safe default provider on this 4 GB host. The temporary unit and copied model
artifact were removed. Repeat the complete proof only after upgrading to at
least 8 GB RAM.

The model files consume about 4.1 GiB. Deployment checks the filesystem that
contains the configured model directory and refuses to download unless it has
at least 10 GiB beyond the configured files. With the default PiServ path,
this is the root filesystem; the external `/dev/sda1` SSD is not used for
model files. Keeping the weights outside `HERMES_HOME` prevents Hermes state
backups from archiving reproducible, checksum-pinned model files. Both server units bind only to
`127.0.0.1`, use a `q4_0` KV cache for the 64K benchmark, set a 4 GiB process
address-space cap, and conflict with each other. The cgroup values are enforced
on PiServ. A failed 64K model start must stop rather than enable a fallback or
keep a model resident.

Live benchmarks on 2026-07-31 used a synthetic non-sensitive response check:

| Model | Result | Available memory after response | Throughput |
| --- | --- | ---: | --- |
| Granite 3.3 2B | Visible response; clean shutdown | 650 MiB | 19.2 prompt tok/s; 5.9 generation tok/s |
| Gemma 4 E2B | Visible response; clean shutdown | 1.3 GiB | 19.1 prompt tok/s; 3.7 generation tok/s |

Gemma's initial 64-token probe was truncated because it generated about 102
tokens of `reasoning_content` before its five-token visible response. The
benchmark now uses 128 completion tokens, records the completion reason and
reasoning-channel metadata without storing that reasoning, and fails when a
model finishes without visible content. Both models are provider-migration
candidates for endpoint-only transport; neither is selected as Hermes'
provider. The later guarded full-provider tests showed that both models cross
the 1.5 GiB host reserve on this 4 GB host. Do not start either model here;
repeat the proof only after upgrading to at least 8 GB RAM.

Llama 3.2 1B remains a possible lower-memory comparison but is not included in
the automated download because Meta gates its official source weights behind
licence acceptance. Do not substitute an unverified community conversion; add
it only after the operator accepts the upstream terms, retrieves checksum-pinned
official weights, and records the SHA-256 of a locally generated GGUF artifact.

### Obtain Official Llama 3.2 Source Weights

1. Sign in to Hugging Face and request access at
   <https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct>. Wait until Meta
   approves the request; token authentication alone is insufficient.
2. Create a read-only Hugging Face token with permission to read the approved
   gated repository. Do not store it in Ansible variables, shell history, or
   the repository.
3. On PiServ, install the official client in `admin`'s isolated `pipx`
   environment, then authenticate interactively:

   ```sh
   sudo apt-get install --yes pipx
   pipx install huggingface_hub
   ~/.local/bin/hf auth login
   ```

   Paste the token only into the interactive prompt and decline Git credential
   storage when offered.
4. Confirm both identity and gated-repository access without printing the
   token:

   ```sh
   ~/.local/bin/hf auth whoami
   HF_HUB_DISABLE_PROGRESS_BARS=1 \
     ~/.local/bin/hf download meta-llama/Llama-3.2-1B-Instruct --dry-run
   ```

5. Download the official source snapshot to the Hugging Face cache, convert it
   locally with the pinned llama.cpp converter, record the source revision and
   generated GGUF SHA-256 in the model record, then run the guarded 64K proof.

The client stores the active token under `admin`'s private Hugging Face cache.
Remove it with `~/.local/bin/hf auth logout` when the Pi no longer needs to
download gated models.

After re-enabling local-model management on a future 8 GB-or-larger host, run
one benchmark at a time:

```sh
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/hermes-agent/benchmark-local-model granite-3-3-2b'
ssh admin@PiServ.local \
  'sudo /usr/local/libexec/hermes-agent/benchmark-local-model gemma-4-e2b'
```

Each command writes a synthetic, non-sensitive JSON result under
`/var/lib/hermes-models/benchmark-results/`. It records actual configured
server properties, response timings, memory availability before and after the
response, and cgroup memory figures. The test does not query Cloud Corpus, Home
Assistant, or Hermes tools.

## Verify Persistence

Run the controller-side verifier to test built-in memory and a reviewed local
skill across a dashboard restart, a private Hermes backup, restoration into an
isolated home, and a temporary switch of that restored home to a bounded,
loopback Granite OpenAI-compatible endpoint:

```sh
scripts/verify-hermes-persistence.sh
```

The verifier uses only a generated non-sensitive marker. It requires a selected
and deployed local model, so it is not runnable while local-model management is
disabled on the current 4 GB host. It restarts the
production dashboard without modifying its state, then imports a temporary
clone below `/run` before creating the memory and skill fixtures. Both backup
archives, cloned homes, dashboard, and local model are removed during cleanup;
a power cycle also clears the temporary clone. The backup contains Hermes state,
including built-in memory and local skills, but not checksum-pinned model
weights stored outside `HERMES_HOME`.

The restored clone declares the managed 64K minimum context required by Hermes.
Its temporary Granite server is capped at 8K, two CPU threads, 32 output
tokens, and an address-space limit. The verifier reads its generated marker
from restored built-in memory, resolves the named provider through Hermes, and
sends a minimal Chat Completions request to the resolved endpoint. The reviewed
local skill is asserted after both restart and restore. This proves the state
and provider-transport migration boundaries, not full-agent performance at 8K
or 64K. It avoids an unbounded inference request during a state-persistence
test.

## Deploy

The Hermes backup policy requires the external SSD and the `external-data`
group. Local-model files do not: they use the filesystem containing the
configured model directory, which is the root filesystem on PiServ today.

```sh
findmnt /mnt/external-data
getent group external-data
```

Apply the dedicated playbook:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

The full installation entry point imports this playbook after external storage
and the Home Assistant MQTT Agent.

## Complete ChatGPT Login

Run the prepared operator helper:

```sh
scripts/hermes-chatgpt-login.sh
```

Open each displayed URL, enter its device code, and authorize the ChatGPT Pro
account. Codex CLI and Hermes each maintain their own ChatGPT device session;
the helper runs the Hermes flow only when its provider session is absent. It
then restarts the dashboard and prints the Codex, Hermes, and tool-policy
states.

The underlying first login command is:

```sh
ssh -t admin@PiServ.local \
  'sudo -u hermes-agent -H env \
  CODEX_HOME=/var/lib/hermes-agent/codex \
  codex login --device-auth'
```

Hermes creates its own refresh session. Routine Codex CLI use does not rotate
the Hermes provider token.

## Open the Private Dashboard

Create an SSH tunnel from the operator Mac:

```sh
ssh -N -L 9119:127.0.0.1:9119 admin@PiServ.local
```

Open `http://127.0.0.1:9119`. Keep the dashboard loopback-only until an
authenticated LAN or Tailnet exposure policy is implemented.

## Validate

Verify service, provider, tool policy, and both runtimes:

```sh
ssh admin@PiServ.local '
  sudo systemctl --no-pager status hermes-agent-dashboard.service
  curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9119/
  sudo -u hermes-agent -H env \
    HERMES_HOME=/var/lib/hermes-agent \
    CODEX_HOME=/var/lib/hermes-agent/codex \
    hermes auth status openai-codex
  sudo -u hermes-agent -H env \
    HERMES_HOME=/var/lib/hermes-agent \
    hermes tools list --platform cli
  sudo -u hermes-agent -H env \
    CODEX_HOME=/var/lib/hermes-agent/codex \
    codex login status
'
```

Expected results after login:

- Dashboard service is active and HTTP returns `200`.
- Hermes and Codex report authenticated ChatGPT sessions.
- Only `memory` and `skills` are enabled.
- `terminal`, `file`, `browser`, `code_execution`, and `homeassistant` remain
  disabled.

Complete the first inference test in the dashboard. Do not enable additional
tools as part of the login test.

## Backup and Restore

Run an on-demand full backup:

```sh
ssh admin@PiServ.local \
  'sudo systemctl start hermes-agent-backup.service'
```

Inspect the timer and archives:

```sh
ssh admin@PiServ.local '
  sudo systemctl list-timers hermes-agent-backup.timer --no-pager
  sudo find /mnt/external-data/backups/hermes-agent \
    -maxdepth 1 -type f -name "hermes-backup-*.zip" -printf "%f %s bytes\n"
'
```

Archives include credentials and therefore remain owned by `hermes-agent` in a
`0700` directory. The timer retains 30 days.

Test restore only into a separate temporary Hermes home until the persistence
gate is complete. Never overwrite the live home without a fresh backup and an
explicit maintenance window.

## Recovery

Inspect service logs:

```sh
ssh admin@PiServ.local \
  'sudo journalctl -u hermes-agent-dashboard.service -n 100 --no-pager'
```

Reapply configuration without changing credentials:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

The role does not manage `auth.json`, `.env` secrets, memory, skills, sessions,
or backup contents. Reapplication preserves those runtime-owned files.

# Hermes Agent

## Table of Contents

- [Purpose](#purpose)
- [Current State](#current-state)
- [Planned Inference Routing](#planned-inference-routing)
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

The current deployment has no automatic route selection and keeps the vision
toolset disabled. This is a planned policy, not an active routing feature.

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

The model files consume about 4.1 GiB. Deployment checks the filesystem that
contains the configured model directory and refuses to download unless it has
at least 10 GiB beyond the configured files. With the default PiServ path,
this is the root filesystem; the external `/dev/sda1` SSD is not used for
model files. Keeping the weights outside `HERMES_HOME` prevents Hermes state
backups from archiving reproducible, checksum-pinned model files. Both server units bind only to
`127.0.0.1`, use a `q4_0` KV cache for the 64K benchmark, set a 4 GiB process
address-space cap, and conflict with each other. The configured cgroup memory
values are not currently enforced on PiServ because its boot arguments disable
the memory controller; `LimitAS` remains active. A failed 64K Gemma start must
therefore stop rather than enable a fallback or keep a model resident.

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
provider. A full Hermes capability test with Granite at 64K required about
2.7 GiB resident memory, left about 440 MiB available while consuming swap,
and made the host unreachable over SSH. The 4 GiB address-space cap therefore
remains in place and rejects Granite's full 64K KV-cache allocation before that
operationally unsafe state. Do not repeat a full local-provider test or start a
resident local provider until the cgroup memory controller is enabled and a
bounded resource policy has been validated. Gemma has not passed the full
capability test.

Llama 3.2 1B remains a possible lower-memory comparison but is not included in
the automated download because Meta gates the official GGUF repository behind
its license acceptance. Do not substitute an unverified community conversion;
add it only after the operator accepts the upstream terms and provides an
independently checksum-pinned source.

Run one benchmark at a time:

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

The verifier uses only a generated non-sensitive marker. It restarts the
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

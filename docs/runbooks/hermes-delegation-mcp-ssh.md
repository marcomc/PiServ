# Hermes Delegation MCP over Restricted SSH

## Purpose

Expose one direct `delegate_task(prompt)` MCP tool that runs a bounded Hermes
agent turn on PiServ. This endpoint is separate from `hermes-piserv`, which is
the upstream messaging-conversation bridge and does not execute agent turns.

## Access Model

```text
MCP client on the Mac
  | SSH public-key authentication
  v
codex-hermes-delegate on PiServ
  | forced command, no PTY or forwarding
  v
root-owned wrapper and one-command sudoers rule
  | transient systemd sandbox as hermes-agent (no HASS token)
  v
hermes-agent: delegation MCP adapter
  | argv, no shell
  v
hermes chat --query PROMPT --quiet --source tool
  | exact sudo rule for home-assistant-assist only
  v
root-owned Home Assistant MCP broker wrapper
  | transient DynamicUser sandbox reads the private token file
  v
configured Home Assistant `/api/mcp` target
```

Hermes uses `/var/lib/hermes-agent` for its configured provider, persistent
state, memory, skills, and MCP integrations. The adapter does not filter Home
Assistant tools or add confirmations. Home Assistant's exposed entities and
credentials remain the accepted read/write capability boundary. Acceptance
tests use reads only unless an operator explicitly authorizes a write.

Only delegated CLI turns receive the explicit native Hermes toolsets
`delegation`, `file`, `memory`, `session_search`, `skills`, `terminal`, and
`todo`. The outer server still exposes only `delegate_task`; stateful tools run
inside the real Hermes agent loop and are not emulated as stateless MCP
callbacks. The dashboard and `hermes-piserv` conversations bridge retain their
separate managed policies. The delegated turn also receives the explicitly
configured `home-assistant-assist` MCP toolset.

The wrapper binds a delegation-only config over Hermes's runtime `config.yaml`.
Ansible derives it from the authenticated managed config, preserves provider,
state, and non-credential MCP settings, removes the seven required native
toolsets from the global deny-list, disables memory and skill write staging,
and omits dashboard credentials. It replaces the configured Home Assistant MCP
server with an exact no-argument `sudo` invocation of a root-owned broker. The
delegation service receives neither the Home Assistant token environment nor
access to its private file; its address space is capped with both `MemoryMax`
and `LimitAS`. The broker runs with `DynamicUser=yes`, reads the token only in
its separate transient service, and forwards only bounded JSON-RPC frames to
the configured `/api/mcp` target. Hermes runs with `--yolo` because this
non-interactive endpoint has no approval callback. This policy exists only
inside the transient delegation service; the dashboard and conversations MCP
remain unchanged.

The server and broker have no listening socket. The SSH account is password-locked and
cannot obtain a shell, PTY, forwarding, arbitrary remote command, or general
sudo access. Its wrapper reuses the hardened conversations-MCP transient
systemd sandbox, including `ProtectSystem=strict`, `NoNewPrivileges`, private
temporary storage, root-owned read-only config/policy binds, and an
`InaccessiblePaths` bind over the managed Home Assistant token file.
`ProtectSystem=strict` limits terminal and file writes to the explicitly
writable Hermes home even though recoverable Hermes approval prompts are
disabled for delegated turns.

## Deploy

The tracked defaults enable both MCP SSH endpoints. An ignored local variables
file may override them:

```yaml
piserv_hermes_mcp_ssh_manage: true
piserv_hermes_delegation_mcp_ssh_manage: true
piserv_hermes_delegation_mcp_ssh_copy_admin_authorized_keys: true
```

Apply the Hermes playbook after local validation:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

Automatic key mode copies the same plain `admin` public keys into a separate
forced-command `authorized_keys` file. Set the delegation copy flag to `false`
only for an operator-managed key lifecycle. Select that mode before the first
deployment: the lifecycle provenance refuses a later automatic/manual change
until the existing endpoint is deliberately removed.

## Add a Manual Key

After the first successful manual-mode deployment, use a known administrator
connection to install a local public key. The procedure authenticates this
endpoint's dedicated lifecycle record before it modifies the recovered
`authorized_keys` path, preserves existing plain keys, and is idempotent for
the supplied key. Replace the key path if the Mac uses another key type.

```sh
ssh-keygen -lf ~/.ssh/id_ed25519.pub

cat ~/.ssh/id_ed25519.pub | \
  ssh "admin@${PISERV_IP:-PiServ.local}" \
  'sudo -n /bin/sh -ceu '\''
    state=/usr/local/libexec/hermes-agent/.codex-hermes-delegation-mcp-state.json
    test -f "$state" && test ! -L "$state"
    test "$(/usr/bin/stat -c "%U:%G:%a" -- "$state")" = "root:root:600"
    read_manual_lifecycle() {
      test -f "$state" && test ! -L "$state"
      test "$(/usr/bin/stat -c "%U:%G:%a" -- "$state")" = "root:root:600"
      /usr/bin/python3 - "$state" <<'\''PY'\''
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    state = json.load(source)
if state.get("schema") != "piserv-hermes-mcp-ssh-state-v1":
    raise SystemExit("unexpected lifecycle schema")
user = state.get("mcp_ssh_user")
group = state.get("mcp_ssh_group")
home = state.get("mcp_ssh_home")
keys = state.get("authorized_keys_path")
key_provenance = state.get("key_provenance")
if state.get("phase") != "active":
    raise SystemExit("Hermes delegation MCP SSH lifecycle is not active")
if not all(isinstance(value, str) for value in (user, group, home, keys, key_provenance)):
    raise SystemExit("lifecycle identity is incomplete")
if key_provenance != "manual-operator-managed":
    raise SystemExit("manual keys require manual-operator-managed lifecycle provenance")
if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
    raise SystemExit("unexpected lifecycle user")
if not re.fullmatch(r"[a-z_][a-z0-9_-]*", group):
    raise SystemExit("unexpected lifecycle group")
if not re.fullmatch(r"/var/lib/[a-z0-9_-]+", home):
    raise SystemExit("unexpected lifecycle home")
if keys != f"{home}/.ssh/authorized_keys":
    raise SystemExit("unexpected lifecycle authorized_keys path")
print("|".join((user, group, home, keys)))
PY
    }
    lifecycle_values=$(read_manual_lifecycle)
    IFS="|" read -r user group home keys <<EOF
$lifecycle_values
EOF
    test -n "$user" && test -n "$group" && test -n "$home" && test -n "$keys"

    publication=$(/usr/bin/sudo -n -u "$user" /bin/sh -ceu '\''
      user=$1
      group=$2
      home=$3
      keys=$4
    test -f "$keys" && test ! -L "$keys"
    test "$(/usr/bin/stat -c "%U:%G:%a" -- "$keys")" = "$user:$group:600"

    IFS= read -r key
    test -n "$key"
    case "$key" in
      ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
      *) exit 1 ;;
    esac
    if IFS= read -r extra; then exit 1; fi

    if /usr/bin/grep -Fqx -- "$key" "$keys"; then
      printf "%s\n" unchanged
    else
      key_directory=${keys%/*}
      test -d "$key_directory" && test ! -L "$key_directory"
      test "$(/usr/bin/stat -c "%U:%G:%a" -- "$key_directory")" = "$user:$group:700"
      umask 077
      staged=$(mktemp "${keys}.XXXXXX")
      /usr/bin/awk "1" "$keys" >"$staged"
      printf "%s\n" "$key" >>"$staged"
      chmod 0600 "$staged"
      printf "%s\n" "$staged"
    fi
    '\'' sh "$user" "$group" "$home" "$keys")
    if test "$publication" != unchanged; then
      key_directory=${keys%/*}
      staged=$publication
      test "${staged%/*}" = "$key_directory"
      test -f "$staged" && test ! -L "$staged"
      test "$(/usr/bin/stat -c "%U:%G:%a" -- "$staged")" = "$user:$group:600"
      cleanup_staged() { rm -f -- "$staged"; }
      trap cleanup_staged EXIT

      reauthenticated_lifecycle_values=$(read_manual_lifecycle)
      test "$reauthenticated_lifecycle_values" = "$lifecycle_values"
      mv -- "$staged" "$keys"
      trap - EXIT
    fi
  '\''
```

To rotate a key, add and validate the replacement with this command first.
Then remove the old key through an administrator session only after confirming
the replacement opens the restricted `piserv-hermes-delegate` MCP transport.
Reapply the playbook after any manual key change; it preserves the managed
manual-key file contents.

## Configure SSH

Add a distinct host alias; do not reuse `piserv-hermes-mcp` because its remote
user is permanently bound to `hermes mcp serve`:

```sshconfig
Host piserv-hermes-delegate
  HostName PiServ.local
  User codex-hermes-delegate
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  BatchMode yes
  RequestTTY no
```

If mDNS is unavailable, use the current operator-supplied DHCP address as
`HostName`. Do not guess a previous address.

## Configure Codex

Register a separately named stdio MCP server:

```sh
codex mcp add hermes-delegate-piserv -- \
  ssh -T piserv-hermes-delegate
codex mcp get hermes-delegate-piserv --json
```

The existing registration remains unchanged:

```text
hermes-piserv          -> messaging and conversation bridge
hermes-delegate-piserv -> delegate_task(prompt) agent turn
```

## Configure Other MCP Clients

Claude Desktop, McpOne, and other stdio MCP clients use the same process:

```json
{
  "mcpServers": {
    "hermes-delegate-piserv": {
      "command": "ssh",
      "args": ["-T", "piserv-hermes-delegate"]
    }
  }
}
```

Do not configure an MCP URL or bearer token. SSH key authentication is the
transport credential.

## Validate

Confirm the local SSH resolution:

```sh
ssh -G piserv-hermes-delegate | \
  rg '^(hostname|user|identityfile|batchmode|requesttty) '
```

Confirm the server-side privilege is exactly one no-argument wrapper:

```sh
ssh admin@PiServ.local \
  'sudo -n sudo -l -U codex-hermes-delegate'
```

Exercise MCP initialization, exact tool discovery, and a harmless real Home
Assistant read:

```sh
scripts/test-hermes-delegation-mcp.py \
  --prompt 'Use Home Assistant to report the current state of one exposed entity. Do not change anything.' \
  -- ssh -T piserv-hermes-delegate
```

Then start a new Codex task and invoke
`hermes-delegate-piserv.delegate_task` with an equivalent read-only prompt.
This proves Codex client discovery and the complete Hermes-to-Home-Assistant
path, not only raw SSH transport.

The playbook also runs an isolated `hermes tools list --platform cli` command
inside the delegation sandbox. It must report exactly the approved native
toolsets and the configured `home-assistant-assist` integration. Treat a
successful playbook without that catalog assertion as a failed delegation
deployment.

## Operator Acceptance Matrix

Run this matrix after a delegation policy, Hermes version, or Home Assistant
endpoint change. Choose an approved, reversible entity in ignored local
variables; do not use an entity with uncertain restoration. The state-changing
row requires explicit operator authorization before it runs.

| Check | Procedure | Required evidence |
| --- | --- | --- |
| Exact target state | Read the approved target and sibling directly through Home Assistant, delegate the authorized reversible target transition, then read both again and restore the target. | Target reaches only the requested state; the sibling is unchanged; restoration succeeds. |
| Configured target forwarding | Run the playbook catalog assertion and the raw MCP harness against `piserv-hermes-delegate`. | The catalog lists only `home-assistant-assist`; the delegation response identifies the approved target from the configured Home Assistant endpoint. |
| Source-scoped tool call | Prompt `delegate_task` to use only `home-assistant-assist` for the approved read or authorized transition. Confirm the broker's fixed-target request in the Home Assistant MCP audit/log and retain the redacted method and entity identifier. | One broker-mediated request reaches the configured `/api/mcp` target; no terminal or unrelated MCP source is accepted as proof. |
| Sibling-entity negative | Include a distinct sibling in the before/after direct reads while requesting an action only for the approved target. | The sibling state is byte-for-byte unchanged. |
| Unreachable-dependency negative | In the isolated broker regression fixture, use an unreachable configured endpoint and submit one bounded frame. | The broker returns a bounded MCP error, sends no fallback request, and the delegation configuration remains unchanged. |

Do not substitute successful tool discovery or a generic agent response for any
matrix row. Record the command, observed result, and any follow-up in this
runbook after each live acceptance.

## Recorded Acceptance

On 2026-08-14, `ansible-playbook ansible/playbooks/hermes-agent.yml` completed
with `failed=0`. The raw MCP harness completed a read-only Home Assistant
request through `delegate_task`, reporting `Lampadina Salotto: on, brightness
38% (Salotto)`; no Home Assistant write was issued.

On 2026-08-15 Europe/Rome (2026-08-14 UTC), the updated Codex client invoked
`hermes-delegate-piserv.delegate_task` through the registered SSH stdio server.
Hermes reported one exposed Home Assistant media-player entity as `off`; no
changes were made. This completed client discovery and the harmless end-to-end
read acceptance for the original delegation deployment. The hardened broker
deployment requires the matrix above before it can claim an equivalent live
acceptance.

On 2026-08-15, the targeted hardened deployment completed with `failed=0`.
The sandboxed catalog listed exactly `delegation`, `file`, `memory`,
`session_search`, `skills`, `terminal`, and `todo`, plus only
`home-assistant-assist`. A `tools/list` request sent through the exact
`hermes-agent` broker sudo rule reached the configured Home Assistant MCP target
and returned its tool catalog; no entity state or other Home Assistant data was
changed. The state-changing matrix row remains pending explicit operator
authorization.

## Revoke and Roll Back

Remove the local client registration without changing PiServ:

```sh
codex mcp remove hermes-delegate-piserv
```

To revoke server access immediately, empty the dedicated
`/var/lib/codex-hermes-delegate/.ssh/authorized_keys` file through an
administrator session. The steady-state playbook does not delete an active
access path. A permanent removal requires an explicit teardown that removes
the dedicated account, SSH match block, sudoers rule, wrapper, and adapter.

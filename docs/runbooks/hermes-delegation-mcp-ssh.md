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
  | transient systemd sandbox as hermes-agent
  v
hermes-agent: delegation MCP adapter
  | argv, no shell
  v
hermes chat --query PROMPT --quiet --source tool
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
state, and MCP settings, removes the seven required native toolsets from the
global deny-list, disables memory and skill write staging, and omits dashboard
credentials. Hermes runs with `--yolo` because this non-interactive endpoint
has no approval callback. This policy exists only inside the transient
delegation service; the dashboard and conversations MCP remain unchanged.

The server has no listening socket. The SSH account is password-locked and
cannot obtain a shell, PTY, forwarding, arbitrary remote command, or general
sudo access. Its wrapper reuses the hardened conversations-MCP transient
systemd sandbox, including `ProtectSystem=strict`, `NoNewPrivileges`, private
temporary storage, root-owned read-only config/policy binds, and the managed
Home Assistant environment file. `ProtectSystem=strict` limits terminal and
file writes to the explicitly writable Hermes home even though recoverable
Hermes approval prompts are disabled for delegated turns.

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
only for an operator-managed key lifecycle.

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

## Recorded Acceptance

On 2026-08-14, `ansible-playbook ansible/playbooks/hermes-agent.yml` completed
with `failed=0`. The raw MCP harness completed a read-only Home Assistant
request through `delegate_task`, reporting `Lampadina Salotto: on, brightness
38% (Salotto)`; no Home Assistant write was issued.

Codex CLI 0.147.0 registered and started
`hermes-delegate-piserv.delegate_task`, but cancelled both the Home Assistant
read and a minimal no-tool turn after about ten seconds, despite configured
`tool_timeout_sec = 360`. Treat Codex-client acceptance as pending until that
client-side cancellation behavior is resolved or a newer CLI is validated.

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

# Hermes MCP over Restricted SSH

## Purpose

Expose the PiServ Hermes MCP server only through an authenticated SSH stdio
session from Codex. The server has no network listener: each Codex MCP session
starts `hermes mcp serve` and it exits when the SSH connection closes.

## Access Model

```text
Codex on the Mac
  │ SSH public-key authentication
  ▼
codex-hermes-mcp on PiServ
  │ forced command, no PTY or forwarding
  ▼
root-owned wrapper and one-command sudoers rule
  ▼
hermes-agent: hermes mcp serve
```

`codex-hermes-mcp` is password-locked and has no shell capability. An
`sshd_config.d` `Match User` policy enforces the MCP forced command and
disables forwarding and PTYs for every authenticated key, including manually
managed keys. Automatically copied keys also receive OpenSSH `restrict` as
defense in depth. Its exact non-interactive sudo command disables sudo's
pseudo-terminal to preserve raw MCP stdio. The wrapper clears the login
environment, suppresses Python warnings that would otherwise pollute stdio
startup diagnostics, and starts Hermes from the established `hermes-agent`
state directory.

The account is intentionally distinct from `hermes-agent`. The latter remains
a non-login service account and continues to own Hermes credentials, skills,
memory, and sessions.

## Configure

Copy or edit the ignored local variables file:

```sh
cp -n ansible/vars/hermes-agent.yml.example ansible/vars/hermes-agent.yml
```

The project defaults enable the dedicated account and copy each currently
authorized `admin` public key, restricted to the MCP forced command. They are
also available when an older ignored local variables file is present:

```yaml
piserv_hermes_mcp_ssh_manage: true
piserv_hermes_mcp_ssh_copy_admin_authorized_keys: true
```

Set either value to `false` in the ignored local variables file only when a
different access lifecycle is intended.

The source is deliberately fixed to `/home/admin/.ssh/authorized_keys`. It
must be a `0600`, regular file owned by `admin`; the playbook fails rather than
copying from another location. It must contain at least one plain public key;
entries with SSH options are rejected rather than being composed unsafely.
Reapplying the playbook refreshes the restricted copy after an `admin` key
rotation.

For manually managed keys, set the copy flag to `false`. The first apply creates
an empty, `0600` `authorized_keys` file. Later applies preserve its contents;
add or remove plain public keys as the operator. The server-side `Match User`
policy continues to enforce the MCP command for every such key.

After the first successful apply, the playbook records the configured account,
paths, and key-management mode in a root-owned lifecycle record. It refuses an
identity, path, or automatic/manual-mode change until the existing deployment
has been removed deliberately; this prevents an old account from retaining an
unrestricted SSH login.

Apply the dedicated playbook:

```sh
ansible-playbook ansible/playbooks/hermes-agent.yml
```

## Add a Manual Key

Use a known administrator connection to install a local public key. Replace
the key path if the Mac uses another key type.

```sh
ssh-keygen -lf ~/.ssh/id_ed25519.pub

cat ~/.ssh/id_ed25519.pub | \
  ssh "admin@${PISERV_IP:-PiServ.local}" \
  'sudo -u codex-hermes-mcp /bin/sh -ceu '\''
    keys=/var/lib/codex-hermes-mcp/.ssh/authorized_keys
    test -f "$keys" && test ! -L "$keys"
    test "$(/usr/bin/stat -c "%U:%G:%a" -- "$keys")" = "codex-hermes-mcp:codex-hermes-mcp:600"

    IFS= read -r key
    test -n "$key"
    case "$key" in
      ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *) ;;
      *) exit 1 ;;
    esac
    if IFS= read -r extra; then exit 1; fi

    /usr/bin/grep -Fqx -- "$key" "$keys" || printf "%s\\n" "$key" >> "$keys"
  '\'''
```

The command first validates the local key, then validates that Ansible's
dedicated regular file still has its expected identity and `0600` mode. It runs
as `codex-hermes-mcp`, appends only a non-duplicate plain public-key line, and
does not rewrite existing keys. Re-run the playbook to repair ownership or mode
drift rather than using a root-owned redirection.

## Configure an SSH Client

Use the same private key that corresponds to an `admin` key copied by automatic
mode, or the public key added through manual mode. Create a host alias in the
Mac user's `~/.ssh/config`:

```sshconfig
Host piserv-hermes-mcp
  HostName PiServ.local
  User codex-hermes-mcp
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  BatchMode yes
  RequestTTY no
```

Replace `IdentityFile` with the matching private key. If mDNS/DNS is
unavailable, use the current operator-supplied DHCP address as `HostName`; do
not guess an old PiServ address.

Validate only the local SSH client resolution before registering an MCP client:

```sh
ssh -G piserv-hermes-mcp | rg '^(hostname|user|identityfile|batchmode|requesttty) '
```

Do not add a `LocalForward`, `RemoteForward`, or `ProxyCommand`: MCP is carried
on the SSH standard streams and the server key policy rejects forwarding.

## Configure Codex Client

This adds a local Codex configuration entry; it does not open a network
listener on PiServ.

```sh
codex mcp add hermes-piserv -- \
  ssh -T piserv-hermes-mcp
```

Inspect the registered command and start a new Codex task:

```sh
codex mcp get hermes-piserv --json
```

Codex starts a new SSH/MCP process when it needs Hermes. Hermes persistent
state remains in `/var/lib/hermes-agent`; the transient stdio process does not
need to stay active between tasks.

## Configure Another MCP Client

This is a stdio MCP server, not an HTTP endpoint. A compatible client must run
the following process, preserving stdin and stdout exactly:

```text
ssh -T piserv-hermes-mcp
```

For clients that use JSON configuration, the equivalent shape is:

```json
{
  "mcpServers": {
    "hermes-piserv": {
      "command": "ssh",
      "args": ["-T", "piserv-hermes-mcp"]
    }
  }
}
```

Do not configure a URL, bearer token, or HTTP transport for this endpoint. The
SSH key is the client credential and every new connection starts a fresh MCP
stdio process.

## Validate

Validate the restricted sudo policy from an administrator session:

```sh
ssh "admin@${PISERV_IP:-PiServ.local}" \
  'sudo -n sudo -l -U codex-hermes-mcp'
```

Expected: exactly one no-argument command,
`/usr/local/libexec/hermes-agent/codex-mcp-ssh`, and no broad sudo rule.

Then start a new Codex task and ask it to list the `hermes-piserv` MCP tools.
This is a transport smoke test only: it proves SSH authentication, the forced
command, and MCP initialization. It does not prove that Hermes can reach the
configured Home Assistant target or that a discovered tool affects only its
intended entity. A raw `ssh` test is deliberately not useful because the
forced command starts the MCP protocol rather than a shell.

## Operator Acceptance Matrix

Complete this matrix after every first deployment, target change, or Hermes
tool-policy change. Use a fresh Codex task with `hermes-piserv`; record the
actual tool name, target, entity identifier, command/result, and timestamp in
the change record. The placeholders are deliberately not executable defaults:
choose existing, approved values from the live MCP tool list and Home Assistant
configuration.

| Acceptance | Operator action in the MCP client | Required evidence |
| --- | --- | --- |
| Transport smoke | List `hermes-piserv` tools. | The expected restricted tool set is returned. This proves transport only. |
| Approved reversible entity | Select `<approved-reversible-entity>` and its exact permitted transition `<before-state>` to `<after-state>`. Invoke the discovered tool, then query the entity through the same MCP client. Restore `<before-state>` and query again. | Both observed states exactly match the selected transition and restoration. Record the tool name and entity identifier. |
| Configured target forwarding | Invoke the tool selected above against `<configured-target>` and inspect the target's own entity state or event history. | The configured target, rather than a local/default or alternate target, receives the request and reports the expected state transition. |
| Sibling-entity negative | With the same tool call, query `<sibling-entity-not-approved>` before and after the approved transition. | The sibling's state and history are unchanged. Any sibling mutation is a failure. |
| Unreachable-dependency negative | Temporarily make the selected dependency unreachable using an approved, reversible test method. Invoke the same tool once, then restore reachability. | The MCP call fails visibly, no requested entity state changes, and Hermes succeeds again only after the dependency is restored. |

Do not substitute a successful tool-list response for any matrix row. Do not
test destructive actions or an entity whose restoration is uncertain. If the
tool set cannot express a scoped, reversible entity transition, stop and record
the missing acceptance contract before granting the MCP client operational use.

To remove the local Codex client configuration without changing PiServ:

```sh
codex mcp remove hermes-piserv
```

## Rollback

The normal convergence playbook deliberately does not delete an active remote
access path. For a failed pre-lifecycle deployment or an intentional teardown,
first remove the local Codex MCP entry, then run this explicit administrator
operation from a host with existing `admin` access:

```sh
ssh "admin@${PISERV_IP:-PiServ.local}" 'sudo -n sh -eu -c '\''
  rm -f -- /etc/sudoers.d/codex-hermes-mcp \
    /usr/local/libexec/hermes-agent/codex-mcp-ssh \
    /etc/ssh/sshd_config.d/60-codex-hermes-mcp.conf \
    /usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json
  rm -rf -- /var/lib/codex-hermes-mcp
  userdel codex-hermes-mcp 2>/dev/null || true
  groupdel codex-hermes-mcp 2>/dev/null || true
  sshd -t
  systemctl reload ssh
'\'''
```

Then confirm that no account, keys, wrapper, SSH drop-in, sudoers policy, or
lifecycle record remains:

```sh
ssh "admin@${PISERV_IP:-PiServ.local}" \
  'getent passwd codex-hermes-mcp; test ! -e /var/lib/codex-hermes-mcp/.ssh/authorized_keys; test ! -e /usr/local/libexec/hermes-agent/codex-mcp-ssh; test ! -e /etc/ssh/sshd_config.d/60-codex-hermes-mcp.conf; test ! -e /etc/sudoers.d/codex-hermes-mcp; test ! -e /usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json'
```

The verification command must exit successfully and produce no account entry
before a clean apply or `piserv_hermes_mcp_ssh_manage: false` is used.

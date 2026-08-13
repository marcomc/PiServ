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
access path. For an intentional teardown, first remove the local Codex MCP
entry. The following operation recovers the account, group, home, key,
wrapper, and sudoers paths from the root-owned lifecycle record; do not replace
those recovered values with the documented defaults. It fails closed on a
missing or invalid lifecycle record, symlink, unexpected owner/mode, unmanaged
marker, unexpected `/etc/skel` file, non-empty home, group member, or any other
passwd record whose primary GID is the target group; it deletes nothing in
those cases. The lifecycle record is created before the account, so a current
deployment cannot leave a managed account in a pre-lifecycle state. Run it from
a host with existing `admin` access:

```sh
ssh "admin@${PISERV_IP:-PiServ.local}" 'sudo -n /bin/sh -seu' <<'REMOTE'
# This location is fixed by the allowed wrapper directory. The record itself
# supplies the configured identity and all managed artifact paths below.
state=/usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json
user=
group=
home=
keys=
wrapper=
sudoers=
dropin=/etc/ssh/sshd_config.d/60-codex-hermes-mcp.conf
teardown_deny=/etc/ssh/sshd_config.d/59-codex-hermes-mcp-teardown.conf

require_directory() {
  test -d "$1" && test ! -L "$1"
  test "$(readlink -f -- "$1")" = "$1"
}

require_safe_parent() {
  require_directory "$1"
  metadata=$(stat -c '%U:%a' -- "$1")
  test "${metadata%%:*}" = root
  mode=${metadata#*:}
  case "$mode" in
    [0-7][0145][0145]) ;;
    *)
      printf 'refusing unsafe parent directory: %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

require_regular() {
  test -f "$1" && test ! -L "$1"
  test "$(readlink -f -- "$1")" = "$1"
  test "$(stat -c '%U:%G:%a' -- "$1")" = "$2"
}

require_private_directory() {
  require_directory "$1"
  test "$(stat -c '%U:%G:%a' -- "$1")" = "$2"
}

require_marker() {
  grep -Fq -- "$2" "$1"
}

require_exact_line() {
  grep -Fxq -- "$2" "$1"
}

path_exists_or_is_symlink() {
  test -e "$1" || test -L "$1"
}

# Authenticate containment before touching a path; none of these parent
# directories is owned by this teardown.
for parent in /etc /etc/ssh /etc/ssh/sshd_config.d /etc/sudoers.d \
  /usr /usr/local /usr/local/libexec /usr/local/libexec/hermes-agent /var /var/lib; do
  require_safe_parent "$parent"
done

# Recover and authenticate the configured lifecycle identity before inspecting
# or changing any target. The parser accepts only the same constrained values
# as the playbook, then emits a delimiter that none of those values can contain.
load_lifecycle_state() {
  require_regular "$state" root:root:600
  lifecycle_values=$(python3 - "$state" <<'PY'
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
wrapper = state.get("wrapper_path")
sudoers = state.get("sudoers_path")
if not all(isinstance(value, str) for value in (user, group, home, keys, wrapper, sudoers)):
    raise SystemExit("lifecycle identity is incomplete")
if not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
    raise SystemExit("unexpected lifecycle user")
if not re.fullmatch(r"[a-z_][a-z0-9_-]*", group):
    raise SystemExit("unexpected lifecycle group")
if not re.fullmatch(r"/var/lib/[a-z0-9_-]+", home):
    raise SystemExit("unexpected lifecycle home")
if keys != f"{home}/.ssh/authorized_keys":
    raise SystemExit("unexpected lifecycle authorized_keys path")
if not re.fullmatch(r"/usr/local/libexec/hermes-agent/[a-z0-9_-]+", wrapper):
    raise SystemExit("unexpected lifecycle wrapper path")
if not re.fullmatch(r"/etc/sudoers\.d/[a-z0-9_-]+", sudoers):
    raise SystemExit("unexpected lifecycle sudoers path")
if state.get("phase") not in {"provisioning", "active"}:
    raise SystemExit("unexpected lifecycle phase")
print("|".join((user, group, home, keys, wrapper, sudoers)))
PY
)
  IFS='|' read -r user group home keys wrapper sudoers <<EOF
$lifecycle_values
EOF
  test -n "$user" && test -n "$group" && test -n "$home" && test -n "$keys"
  test -n "$wrapper" && test -n "$sudoers"
}

# Recover the configured identity before looking up its account or group.
load_lifecycle_state

account_present=false
group_present=false
if getent group "$group" >/dev/null; then
  group_present=true
fi
if getent passwd "$user" >/dev/null; then
  account_present=true
  passwd_record=$(getent passwd "$user")
  group_record=$(getent group "$group")
  test -n "$group_record"
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f6)" = "$home"
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f7)" = /bin/sh
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f3)" != 0
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f4)" = \
    "$(printf '%s\n' "$group_record" | cut -d: -f3)"
  test -z "$(printf '%s\n' "$group_record" | cut -d: -f4)"
fi
if "$group_present" && ! "$account_present"; then
  printf 'refusing to delete an unattested standalone group: %s\n' "$group" >&2
  exit 1
fi
if "$group_present"; then
  group_gid=$(printf '%s\n' "$group_record" | cut -d: -f3)
  test "$group_gid" != 0
  primary_gid_users=$(getent passwd | awk -F: -v user="$user" -v gid="$group_gid" \
    '$1 != user && $4 == gid { print $1 }')
  if test -n "$primary_gid_users"; then
    printf 'refusing to delete a group used as a primary GID by: %s\n' \
      "$primary_gid_users" >&2
    exit 1
  fi
fi

# Authenticate every existing managed artifact. A missing path is accepted only
# later as a resumable stage after the authenticated temporary deny is active.
if path_exists_or_is_symlink "$wrapper"; then
  require_regular "$wrapper" root:root:755
  require_marker "$wrapper" '# Managed by Ansible. This entry point'
fi
if path_exists_or_is_symlink "$dropin"; then
  require_regular "$dropin" root:root:644
  require_marker "$dropin" '# Managed by Ansible. Restrict this principal even when its authorized_keys'
  require_exact_line "$dropin" "Match User $user"
  require_exact_line "$dropin" "    ForceCommand /usr/bin/sudo -n $wrapper"
fi
if path_exists_or_is_symlink "$sudoers"; then
  require_regular "$sudoers" root:root:440
  require_marker "$sudoers" '# Managed by Ansible. Permit only the no-argument Hermes MCP entry point.'
  require_exact_line "$sudoers" "Defaults:$user !use_pty"
  require_exact_line "$sudoers" "$user ALL=(root) NOPASSWD: $wrapper \"\""
  visudo -cf "$sudoers"
fi

# Drain the SSH principal before revoking it. Publish a temporary, root-owned
# deny policy first, validate the complete configuration, then reload SSH. If
# any later check fails, this deny policy intentionally remains in place and no
# deletion has begun, so repair does not reopen the principal accidentally.
expected_deny=$(mktemp)
deny_tmp=
teardown_resume=false
cleanup_teardown_files() {
  rm -f -- "$expected_deny" "${deny_tmp:-}"
}
trap cleanup_teardown_files EXIT
cat >"$expected_deny" <<DENY
# Temporary teardown drain for the dedicated Hermes MCP SSH principal.
Match User $user
    ForceCommand /usr/bin/false
    DisableForwarding yes
    PermitTTY no
    X11Forwarding no
Match all
DENY
if path_exists_or_is_symlink "$teardown_deny"; then
  # Resume a prior safe drain only when its exact root-owned policy remains.
  require_regular "$teardown_deny" root:root:644
  cmp -s -- "$expected_deny" "$teardown_deny"
  teardown_resume=true
else
  deny_tmp=$(mktemp /etc/ssh/sshd_config.d/.codex-hermes-mcp-teardown.XXXXXX)
  cp -- "$expected_deny" "$deny_tmp"
  chown root:root "$deny_tmp"
  chmod 0644 "$deny_tmp"
  sshd -t -f "$deny_tmp"
  mv -- "$deny_tmp" "$teardown_deny"
fi
sshd -t
systemctl reload ssh
effective_deny=$(sshd -T -C "user=${user},addr=127.0.0.1,host=localhost")
printf '%s\n' "$effective_deny" | grep -Fx 'forcecommand /usr/bin/false'
printf '%s\n' "$effective_deny" | grep -Fx 'disableforwarding yes'
printf '%s\n' "$effective_deny" | grep -Fx 'permittty no'
printf '%s\n' "$effective_deny" | grep -Fx 'x11forwarding no'

if "$account_present"; then
  if path_exists_or_is_symlink "$home"; then
    require_directory "$home"
    if path_exists_or_is_symlink "$home/.ssh"; then
      require_private_directory "$home/.ssh" "${user}:${group}:700"
      if path_exists_or_is_symlink "$keys"; then
        require_regular "$keys" "${user}:${group}:600"
      else
        test "$teardown_resume" = true
        test "$(find "$home/.ssh" -xdev -mindepth 1 -print -quit)" = ''
      fi
    else
      test "$teardown_resume" = true
    fi
    # useradd creates this bounded Debian/Raspberry Pi OS skeleton. Authenticate
    # each copy against /etc/skel before accepting and later removing it.
    for skeleton_file in .bash_logout .bashrc .profile; do
      require_regular "/etc/skel/$skeleton_file" root:root:644
      require_regular "$home/$skeleton_file" "${user}:${group}:644"
      cmp -s -- "/etc/skel/$skeleton_file" "$home/$skeleton_file"
    done
    test "$(find "$home" -xdev -mindepth 1 \
      ! -path "$home/.ssh" ! -path "$keys" \
      ! -path "$home/.bash_logout" ! -path "$home/.bashrc" \
      ! -path "$home/.profile" -print -quit)" = ''
  else
    test "$teardown_resume" = true
  fi
elif path_exists_or_is_symlink "$home"; then
  printf 'refusing to leave recovered home without its lifecycle account: %s\n' \
    "$home" >&2
  exit 1
fi

# No new principal session can now authenticate. Refuse if an existing SSH
# session remains: logind records the original authenticated UID even after
# ForceCommand invokes sudo and systemd-run changes child-process identities.
if "$account_present"; then
  user_uid=$(id -u "$user")
  command -v loginctl >/dev/null
  active_sessions=$(loginctl list-sessions --no-legend | \
    awk -v uid="$user_uid" '$2 == uid { print }')
  if test -n "$active_sessions"; then
    printf 'refusing teardown while %s has active SSH sessions\n' \
      "$user" >&2
    test -z "$active_sessions" || printf '%s\n' "$active_sessions" >&2
    exit 1
  fi
fi

sshd -t
if "$account_present"; then
  # Keep the ForceCommand policy live while keys are revoked, so a connection
  # racing this teardown cannot fall back to the account's login shell.
  if path_exists_or_is_symlink "$keys"; then rm -f -- "$keys"; fi
  if path_exists_or_is_symlink "$home/.ssh"; then rmdir -- "$home/.ssh"; fi
  for skeleton_file in .bash_logout .bashrc .profile; do
    rm -f -- "$home/$skeleton_file"
  done
  if path_exists_or_is_symlink "$home"; then rmdir -- "$home"; fi
  userdel "$user"
  if "$group_present"; then groupdel "$group"; fi
fi
rm -f -- "$sudoers" "$wrapper" "$dropin"
sshd -t
systemctl reload ssh
! getent passwd "$user" && ! getent group "$group"
! path_exists_or_is_symlink "$home"
! path_exists_or_is_symlink "$home/.ssh"
! path_exists_or_is_symlink "$keys"
! path_exists_or_is_symlink "$wrapper"
! path_exists_or_is_symlink "$dropin"
! path_exists_or_is_symlink "$sudoers"
rm -f -- "$state"
! path_exists_or_is_symlink "$state"
rm -f -- "$teardown_deny"
sshd -t
systemctl reload ssh
REMOTE
```

The command verifies the recovered identity and every recovered managed path
before it deletes the lifecycle record. It must exit successfully and produce
no account entry before a clean apply or `piserv_hermes_mcp_ssh_manage: false`
is used.

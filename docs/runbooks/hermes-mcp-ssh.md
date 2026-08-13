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
  'sudo -n /bin/sh -ceu '\''
    state=/usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json
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
    raise SystemExit("Hermes MCP SSH lifecycle is not active")
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
      printf '%s\n' unchanged
    else
      key_directory=${keys%/*}
      test -d "$key_directory" && test ! -L "$key_directory"
      test "$(/usr/bin/stat -c "%U:%G:%a" -- "$key_directory")" = "$user:$group:700"
      umask 077
      staged=$(mktemp "${keys}.XXXXXX")
      /usr/bin/awk "1" "$keys" >"$staged"
      printf "%s\n" "$key" >>"$staged"
      chmod 0600 "$staged"
      printf '%s\n' "$staged"
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

      # Re-authenticate the root-owned manual-key policy immediately before
      # atomically replacing the recovered key file with the staged content.
      reauthenticated_lifecycle_values=$(read_manual_lifecycle)
      test "$reauthenticated_lifecycle_values" = "$lifecycle_values"
      mv -- "$staged" "$keys"
      trap - EXIT
    fi
  '\'''
```

The command first authenticates and recovers the active lifecycle identity,
then validates the local key and that Ansible's dedicated `.ssh` directory and
regular key file have the recovered identities and modes. It runs as the
recovered MCP user, atomically publishes a
newline-delimited non-duplicate plain public-key set, including when the
previous final line lacked a newline, and preserves existing keys. Re-run the
playbook after a successful manual change.

### Repair Manual-Key Permissions

Ansible deliberately fails closed if the existing home or `.ssh` directory has
ownership drift, or `authorized_keys` has ownership or mode drift. It can
normalize directory modes, but never normalizes or replaces an existing key
file. Do not use a root-owned redirection to repair the file. While the
lifecycle record is active and says that keys are manually managed, use this
bounded repair procedure instead. It authenticates the
root-owned lifecycle record, confirms the recovered account and group, refuses
missing, non-directory, or symlinked paths, and changes only the three managed
paths to the modes Ansible requires.

```sh
ssh "admin@${PISERV_IP:-PiServ.local}" 'sudo -n /bin/sh -ceu '\''
  state=/usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json
  test -f "$state" && test ! -L "$state"
  test "$(/usr/bin/stat -c "%U:%G:%a" -- "$state")" = "root:root:600"
  lifecycle_values=$(/usr/bin/python3 - "$state" <<'\''PY'\''
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
if state.get("phase") != "active":
    raise SystemExit("Hermes MCP SSH lifecycle is not active")
if state.get("key_provenance") != "manual-operator-managed":
    raise SystemExit("manual permission repair requires manual key provenance")
if not all(isinstance(value, str) for value in (user, group, home, keys)):
    raise SystemExit("lifecycle identity is incomplete")
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
)
  IFS="|" read -r user group home keys <<EOF
$lifecycle_values
EOF
  test -n "$user" && test -n "$group" && test -n "$home" && test -n "$keys"
  ssh_directory=${keys%/*}

  passwd_record=$(getent passwd "$user")
  group_record=$(getent group "$group")
  test -n "$passwd_record" && test -n "$group_record"
  IFS=: read -r _ _ user_uid user_gid _ account_home _ <<EOF
$passwd_record
EOF
  IFS=: read -r _ _ group_gid _ <<EOF
$group_record
EOF
  test "$user_uid" != 0 && test "$user_gid" != 0 && test "$group_gid" != 0
  test "$user_gid" = "$group_gid" && test "$account_home" = "$home"
  test -d "$home" && test ! -L "$home"
  test -d "$ssh_directory" && test ! -L "$ssh_directory"
  test -f "$keys" && test ! -L "$keys"

  chown -- "$user:$group" "$home" "$ssh_directory" "$keys"
  chmod 0750 "$home"
  chmod 0700 "$ssh_directory"
  chmod 0600 "$keys"
  test "$(/usr/bin/stat -c "%U:%G:%a" -- "$home")" = "$user:$group:750"
  test "$(/usr/bin/stat -c "%U:%G:%a" -- "$ssh_directory")" = "$user:$group:700"
  test "$(/usr/bin/stat -c "%U:%G:%a" -- "$keys")" = "$user:$group:600"
'\''
```

If any check fails, do not weaken the Ansible preflight or broaden this command;
inspect the unexpected state and use the intentional teardown procedure below
before a clean reprovisioning.

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
marker, unexpected legacy skeleton file, non-empty home, group member, or any other
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

require_expected_home_filesystem() {
  # The managed home must remain an ordinary directory on the same filesystem
  # as its fixed /var/lib parent. A mount or a different source/filesystem can
  # turn a bounded rmdir into an operation on operator-managed storage.
  command -v findmnt >/dev/null
  command -v mountpoint >/dev/null
  test ! -L "$home"
  test ! -L /var/lib
  expected_home_filesystem=$(findmnt --noheadings --output SOURCE,FSTYPE --target /var/lib | \
    sed 's/^[[:space:]]*//')
  actual_home_filesystem=$(findmnt --noheadings --output SOURCE,FSTYPE --target "$home" | \
    sed 's/^[[:space:]]*//')
  test -n "$expected_home_filesystem"
  test "$actual_home_filesystem" = "$expected_home_filesystem"
  if mountpoint -q -- "$home"; then
    printf 'refusing teardown of lifecycle home mountpoint: %s\n' "$home" >&2
    exit 1
  fi
  if path_exists_or_is_symlink "$home/.ssh" && mountpoint -q -- "$home/.ssh"; then
    printf 'refusing teardown of lifecycle SSH directory mountpoint: %s\n' \
      "$home/.ssh" >&2
    exit 1
  fi
}

require_marker() {
  grep -Fq -- "$2" "$1"
}

require_exact_line() {
  grep -Fxq -- "$2" "$1"
}

require_safe_sshd_config_fragment() {
  test -f "$1" && test ! -L "$1"
  test "$(readlink -f -- "$1")" = "$1"
  test "$(stat -c '%U:%G' -- "$1")" = root:root
  fragment_mode=$(stat -c '%a' -- "$1")
  case "$fragment_mode" in
    [0-7][0145][0145]) ;;
    *)
      printf 'refusing unsafe SSH configuration fragment mode: %s (%s)\n' \
        "$fragment_mode" "$1" >&2
      exit 1
      ;;
  esac
}

require_unscoped_preceding_match_context() {
  # The main configuration determines the include graph. Accept only the
  # standard Debian drop-in glob, then inspect every preceding fragment before
  # the temporary 59-* policy. A scoped Match or another Include can change
  # the context in which that policy is read, so fail closed rather than
  # relying on fragment-local parsing.
  test -f /etc/ssh/sshd_config && test ! -L /etc/ssh/sshd_config
  test "$(readlink -f -- /etc/ssh/sshd_config)" = /etc/ssh/sshd_config
  test "$(stat -c '%U:%G' -- /etc/ssh/sshd_config)" = root:root
  main_mode=$(stat -c '%a' -- /etc/ssh/sshd_config)
  case "$main_mode" in
    [0-7][0145][0145]) ;;
    *)
      printf 'refusing unsafe main SSH configuration mode: %s\n' "$main_mode" >&2
      exit 1
      ;;
  esac
  main_context=$(awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      lower = tolower(line)
      if (lower ~ /^#/) next
      if (lower ~ /^match[[:space:]]/ &&
          lower !~ /^match[[:space:]]+all([[:space:]]|$)/) {
        print FILENAME ":" line
      }
      if (lower ~ /^include[[:space:]]/ &&
          lower !~ /^include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf([[:space:]]+#.*)?$/) {
        print FILENAME ":" line
      }
    }
  ' /etc/ssh/sshd_config)
  if test -n "${main_context}"; then
    printf 'refusing SSH teardown with scoped Match directives or unproven Includes in the main configuration:\n%s\n' \
      "${main_context}" >&2
    exit 1
  fi
  # Authenticate every fragment before treating its contents as configuration.
  # The glob intentionally also reaches symlinks and non-regular names, which
  # the helper rejects rather than silently omitting them from this proof.
  for sshd_fragment in /etc/ssh/sshd_config.d/*.conf; do
    test -e "$sshd_fragment" || test -L "$sshd_fragment" || continue
    require_safe_sshd_config_fragment "$sshd_fragment"
  done
  symlinked_fragments=$(find /etc/ssh/sshd_config.d -xdev -maxdepth 1 -type l \
    -name '*.conf' -print | LC_ALL=C sort)
  if test -n "${symlinked_fragments}"; then
    printf 'refusing SSH teardown with symlinked configuration fragments:\n%s\n' \
      "${symlinked_fragments}" >&2
    exit 1
  fi
  preceding_context=$(find /etc/ssh/sshd_config.d -xdev -maxdepth 1 -type f \
    -name '*.conf' ! -name '59-codex-hermes-mcp-teardown.conf' -print | \
    LC_ALL=C sort | awk -v deny="${teardown_deny}" '
      $0 < deny {
        path = $0
        while ((getline line < path) > 0) {
          sub(/^[[:space:]]+/, "", line)
          lower = tolower(line)
          if (lower !~ /^#/ &&
              ((lower ~ /^match[[:space:]]/ &&
                lower !~ /^match[[:space:]]+all([[:space:]]|$)/) ||
               lower ~ /^include[[:space:]]/)) {
            print path ":" line
          }
        }
        close(path)
      }
    ')
  if test -n "${preceding_context}"; then
    printf 'refusing SSH teardown with preceding scoped Match directives or Includes:\n%s\n' \
      "${preceding_context}" >&2
    exit 1
  fi
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
group_only_resume=false
if getent group "$group" >/dev/null; then
  group_present=true
  group_record=$(getent group "$group")
  test -n "$group_record"
  group_gid=$(printf '%s\n' "$group_record" | cut -d: -f3)
  test "$group_gid" != 0
  test -z "$(printf '%s\n' "$group_record" | cut -d: -f4)"
fi
if getent passwd "$user" >/dev/null; then
  account_present=true
  passwd_record=$(getent passwd "$user")
  test "$group_present" = true
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f6)" = "$home"
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f7)" = /bin/sh
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f3)" != 0
  test "$(printf '%s\n' "$passwd_record" | cut -d: -f4)" = \
    "$(printf '%s\n' "$group_record" | cut -d: -f3)"
fi
if "$group_present" && ! "$account_present"; then
  # A prior run can stop after userdel but before groupdel. Accept this only
  # after the exact authenticated temporary deny below proves it is a resume.
  group_only_resume=true
fi
if "$group_present"; then
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
teardown_drain_verified=false
cleanup_teardown_files() {
  rm -f -- "$expected_deny" "${deny_tmp:-}"
}
trap cleanup_teardown_files EXIT
require_unscoped_preceding_match_context
cat >"$expected_deny" <<DENY
# Temporary teardown drain for the dedicated Hermes MCP SSH principal.
Match User $user
    ForceCommand /usr/bin/false
    DisableForwarding yes
    PermitTTY no
    PermitUserRC no
    X11Forwarding no
Match all
DENY
if path_exists_or_is_symlink "$teardown_deny"; then
  # Resume a prior safe drain only when its exact root-owned policy remains.
  require_regular "$teardown_deny" root:root:644
  cmp -s -- "$expected_deny" "$teardown_deny"
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
printf '%s\n' "$effective_deny" | grep -Fx 'permituserrc no'
printf '%s\n' "$effective_deny" | grep -Fx 'x11forwarding no'
teardown_drain_verified=true

# A standalone group is permitted only after the exact deny policy has been
# installed and proven effective. The lifecycle record and earlier GID and
# membership checks still prove it is safe to delete.
if "$group_only_resume"; then
  test "$teardown_drain_verified" = true
fi

# Debian's USERGROUPS_ENAB policy can remove the account's private group as part
# of userdel. Re-check instead of treating the earlier lookup as a promise:
# an interrupted, already-drained teardown is safe whether that group remains
# for this command or was removed with the account.
remove_private_group_if_present() {
  if getent group "$group" >/dev/null; then
    groupdel "$group"
  fi
}

if "$account_present"; then
  if path_exists_or_is_symlink "$home"; then
    require_directory "$home"
    require_expected_home_filesystem
    if path_exists_or_is_symlink "$home/.ssh"; then
      require_private_directory "$home/.ssh" "${user}:${group}:700"
      if path_exists_or_is_symlink "$keys"; then
        require_regular "$keys" "${user}:${group}:600"
      else
        test "$teardown_drain_verified" = true
        test "$(find "$home/.ssh" -xdev -mindepth 1 -print -quit)" = ''
      fi
    else
      test "$teardown_drain_verified" = true
    fi
    # Current provisioning creates the dedicated home explicitly and keeps it
    # empty. Older deployments can contain these bounded useradd skeleton paths;
    # authenticate and remove any that remain, but accept a current clean home.
    # Do not compare against mutable /etc/skel content. Unexpected files still
    # make the bounded-home check fail closed.
    for skeleton_file in .bash_logout .bashrc .profile; do
      if path_exists_or_is_symlink "$home/$skeleton_file"; then
        require_regular "$home/$skeleton_file" "${user}:${group}:644"
      fi
    done
    test "$(find "$home" -xdev -mindepth 1 \
      ! -path "$home/.ssh" ! -path "$keys" \
      ! -path "$home/.bash_logout" ! -path "$home/.bashrc" \
      ! -path "$home/.profile" -print -quit)" = ''
  else
    test "$teardown_drain_verified" = true
  fi
elif path_exists_or_is_symlink "$home"; then
  printf 'refusing to leave recovered home without its lifecycle account: %s\n' \
    "$home" >&2
  exit 1
fi

# No new principal session can now authenticate. Refuse if an existing SSH
# session remains. Inspect the root-owned sshd session process first: unlike
# logind, it remains available when sshd is configured with UsePAM no. The
# session process preserves the authenticated principal even after
# ForceCommand invokes sudo and systemd-run changes child-process identities.
if "$account_present"; then
  command -v ps >/dev/null
  active_sshd_sessions=$(ps -eo pid=,user=,comm=,args= | \
    awk -v user="$user" '
      $2 == "root" && $3 == "sshd" &&
      (index($0, "sshd: " user " [priv]") || index($0, "sshd: " user "@")) {
        print
      }
    ')
  if test -n "$active_sshd_sessions"; then
    printf 'refusing teardown while %s has active SSH session processes\n' \
      "$user" >&2
    printf '%s\n' "$active_sshd_sessions" >&2
    exit 1
  fi

  # When PAM is enabled, retain logind as an independent, broader check. Do
  # not require it: UsePAM no installations do not create a logind session.
  user_uid=$(id -u "$user")
  if command -v loginctl >/dev/null; then
    active_sessions=$(loginctl list-sessions --no-legend | \
      awk -v uid="$user_uid" '$2 == uid { print }')
    if test -n "$active_sessions"; then
      printf 'refusing teardown while %s has active SSH sessions\n' \
        "$user" >&2
      printf '%s\n' "$active_sessions" >&2
      exit 1
    fi
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
  remove_private_group_if_present
elif "$group_only_resume"; then
  remove_private_group_if_present
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
# Keep the authenticated lifecycle record until the temporary deny policy has
# been removed and SSH has accepted and reloaded the final configuration. If
# either step fails, the record remains for a safe retry; the account and keys
# have already been removed, so the absence of the temporary deny is harmless.
rm -f -- "$teardown_deny"
sshd -t
systemctl reload ssh
rm -f -- "$state"
! path_exists_or_is_symlink "$state"
REMOTE
```

The command verifies the recovered identity and every recovered managed path
before it deletes the lifecycle record, and deletes that record only after the
temporary deny policy has been removed and SSH has accepted and reloaded the
final configuration. It must exit successfully and produce
no account entry before a clean apply or `piserv_hermes_mcp_ssh_manage: false`
is used.

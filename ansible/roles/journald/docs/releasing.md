# Releasing

## Purpose

Publish the journald role to Ansible Galaxy from a standalone public role
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Set in metadata |
| Galaxy role name | `journald` | Set in metadata |
| Source role path | `/path/to/ansible/roles/journald/` | Example |
| Standalone repository name | `ansible-journald` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Unreleased |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.15` | Role metadata |

## Export Role

Galaxy imports standalone roles from a public GitHub repository whose root is
the role root. Export this subrole into a standalone repository before import.

```sh
src="/path/to/ansible/roles/journald"
dst="/path/to/ansible-journald"

mkdir -p "$dst"
rsync -a --delete \
  --exclude '.git/' \
  "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
role_root=$(pwd)
tmp_dir=$(mktemp -d)
mkdir -p "$tmp_dir/roles"
ln -s "$role_root" "$tmp_dir/roles/journald"
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --syntax-check tests/test.yml
rm -rf "$tmp_dir"
ansible-lint .
rg -n 'password|secret|token|private' . --glob '!docs/releasing.md'
```

## Release

Create and push a SemVer tag from the standalone public repository:

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin main
git push origin v0.1.0
```

Import the role into Ansible Galaxy:

```sh
ansible-galaxy role import marcomc ansible-journald \
  --branch main \
  --role-name journald \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status:

```sh
ansible-galaxy role import --status marcomc ansible-journald \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check published role metadata:

```sh
ansible-galaxy role info marcomc.journald
```

Verify a pinned install:

```sh
tmp_dir=$(mktemp -d)
ansible-galaxy role install --roles-path "$tmp_dir" marcomc.journald,0.1.0
rm -rf "$tmp_dir"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Galaxy imports wrong files | Confirm the public repository root is the role root |
| Galaxy metadata is stale | Confirm the branch and tag are pushed before import |
| Version is absent | Confirm the tag uses `v0.1.0` or another SemVer tag |
| Token failure | Confirm `ANSIBLE_GALAXY_TOKEN` is set in the shell |
| Role name mismatch | Confirm `meta/main.yml` and `--role-name` match |

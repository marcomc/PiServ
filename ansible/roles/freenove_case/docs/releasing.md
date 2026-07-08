# Releasing

## Purpose

Publish the Freenove Case role to Ansible Galaxy from a standalone public role
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Assumed |
| Galaxy role name | `freenove_case` | Set in metadata |
| Source role path | `/path/to/ansible/roles/freenove_case/` | Example |
| Standalone repo name | `freenove_case` | Assumed |
| Default branch | `main` | Current local branch |
| Initial version | `0.1.0` | Assumed |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.15` | Role metadata |

## Export Role

Galaxy imports standalone roles from a public GitHub repository whose root is
the role root. Export this subrole into a standalone repository before import.

Example:

```sh
src="/path/to/ansible/roles/freenove_case"
dst="/path/to/freenove_case"

mkdir -p "$dst"
rsync -a --delete \
  --exclude '.git/' \
  "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
rg -n 'password|secret|token' . --glob '!docs/releasing.md'
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
ansible-galaxy role import marcomc freenove_case \
  --branch main \
  --role-name freenove_case \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status:

```sh
ansible-galaxy role import --status marcomc freenove_case \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check published role metadata:

```sh
ansible-galaxy role info marcomc.freenove_case
```

Verify pinned install:

```sh
tmp_dir="$(mktemp -d)"
ansible-galaxy role install --roles-path "$tmp_dir" marcomc.freenove_case,0.1.0
rm -rf "$tmp_dir"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Galaxy imports wrong files | Confirm the public repo root is the role root |
| Galaxy metadata is stale | Confirm tag and branch pushed before import |
| Version not visible | Confirm the tag uses `v0.1.0` or another SemVer tag |
| Token failure | Confirm `ANSIBLE_GALAXY_TOKEN` is set in the shell |
| Role name mismatch | Confirm `meta/main.yml` and import `--role-name` match |

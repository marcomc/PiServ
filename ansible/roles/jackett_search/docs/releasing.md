# Releasing

## Purpose

Publish the jackett_search role to Ansible Galaxy from a standalone public role
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Set in metadata |
| Galaxy role name | `jackett_search` | Set in metadata |
| Source role path | `/path/to/ansible/roles/jackett_search/` | Example |
| Standalone repo name | `ansible-jackett-search` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Unreleased |
| License | MIT | Set in metadata |
| Minimum Ansible version | `2.15` | Set in metadata |

## Export Role

Ansible Galaxy imports standalone roles from a public GitHub repository whose
root is the role root. Export this subrole before import.

```sh
src="/path/to/ansible/roles/jackett_search"
dst="/path/to/ansible-jackett-search"

mkdir -p "$dst"
rsync -a --delete --exclude '.git/' "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
ansible-playbook -i tests/inventory tests/test.yml
ansible-lint .
rg -n 'api_key|password|secret|token' . --glob '!docs/releasing.md'
```

Review every hit before publication. The API key must never be committed.

## Release

Create and push a SemVer tag from the standalone public repository:

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin main
git push origin v0.1.0
```

Import the role into Ansible Galaxy:

```sh
ansible-galaxy role import marcomc ansible-jackett-search \
  --branch main \
  --role-name jackett_search \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status and published metadata:

```sh
ansible-galaxy role import --status marcomc ansible-jackett-search \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role info marcomc.jackett_search
```

Verify a pinned install:

```sh
tmp_dir="$(mktemp -d)"
ansible-galaxy role install --roles-path "$tmp_dir" marcomc.jackett_search,0.1.0
rm -rf "$tmp_dir"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Galaxy imports wrong files | Confirm the public repository root is the role root |
| Metadata is stale | Confirm the branch and SemVer tag are pushed before import |
| Version is not visible | Confirm the tag uses `v0.1.0` or another SemVer tag |
| Token failure | Confirm `ANSIBLE_GALAXY_TOKEN` is set in the shell |
| Role name mismatch | Confirm `meta/main.yml` and `--role-name` match |

# Releasing

## Purpose

Publish the Wi-Fi Watchdog role to Ansible Galaxy from a standalone public
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Inferred from local roles |
| Galaxy role name | `wifi_watchdog` | Set in metadata |
| Source role path | `/path/to/ansible/roles/wifi_watchdog/` | Example |
| Standalone repository name | `ansible-wifi-watchdog` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Planned |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.15` | Role metadata |

Confirm the standalone GitHub repository name and default branch before the
first release. Galaxy imports standalone roles from a public GitHub repository
whose root is the role root.

## Export Role

```sh
src="/path/to/ansible/roles/wifi_watchdog"
dst="/path/to/ansible-wifi-watchdog"

mkdir -p "$dst"
rsync -a --delete --exclude '.git/' "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
rg -n 'password|secret|token|private-email' . --glob '!docs/releasing.md'
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
ansible-galaxy role import marcomc ansible-wifi-watchdog \
  --branch main \
  --role-name wifi_watchdog \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status and published metadata:

```sh
ansible-galaxy role import --status marcomc ansible-wifi-watchdog \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role info marcomc.wifi_watchdog
```

Verify a pinned installation:

```sh
tmp_dir="$(mktemp -d)"
ansible-galaxy role install --roles-path "$tmp_dir" marcomc.wifi_watchdog,0.1.0
rm -rf "$tmp_dir"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Galaxy imports wrong files | The public repository root must be the role root |
| Metadata is stale | The tag and `main` branch must be pushed before import |
| Version is absent | Confirm a SemVer tag such as `v0.1.0` exists |
| Token failure | Confirm `ANSIBLE_GALAXY_TOKEN` is available in the shell |
| Role name mismatch | Confirm metadata and `--role-name` both use `wifi_watchdog` |

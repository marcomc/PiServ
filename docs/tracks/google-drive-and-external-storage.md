# Google Drive and External Storage Proposal

## Table of Contents

- [Scope](#scope)
- [PiServ baseline](#piserv-baseline)
- [Google Drive options](#google-drive-options)
- [Recommended Drive design](#recommended-drive-design)
- [External SSD filesystems](#external-ssd-filesystems)
- [GitHub disaster backup](#github-disaster-backup)
- [Jackett and torrent workload](#jackett-and-torrent-workload)
- [Implementation gates](#implementation-gates)
- [Sources](#sources)

## Scope

This proposal covers the planned Google Drive client, the 4 TB external SSD,
the complete GitHub account backup, Jackett Search, and a torrent client behind
VPN Unlimited. It is a design and validation note; no service or disk is
installed by this document.

## PiServ baseline

The repository documents PiServ as Raspberry Pi OS/Debian 13 `trixie` on
`arm64`, with a Raspberry Pi 5 and 4 GB of RAM. The final implementation must
confirm the live kernel, architecture, USB storage path, free space, and Docker
runtime before applying automation.

## Google Drive options

| Option | Mount | Sync | Scope control | Assessment |
| --- | --- | --- | --- | --- |
| Google Drive for Desktop | No Linux client | No | N/A | Excluded: Google states that the desktop version is unavailable on Linux. |
| `rclone` mount | FUSE virtual filesystem | One-way `copy`/`sync`; bidirectional `bisync` | OAuth scope and `root_folder_id`; filters | Recommended general-purpose client. Mature CLI, systemd-friendly, and supports ARM64 builds. |
| `google-drive-ocamlfuse` | FUSE virtual filesystem | Not a complete synchronization engine | OAuth and mount configuration | Possible fallback for a simple mount, but less suitable as the backup and synchronization control plane. |
| Custom Drive API client | Application-defined | Application-defined | Fine-grained API scopes and folder IDs | Only justified if PiServ later needs workflow-specific Drive operations. |

`rclone` supports full Drive access, read-only access, app-created files only,
and a configured root folder. Google documents the restricted `drive` and
`drive.readonly` scopes, while `drive.file` limits access to files selected or
created by the application. A folder-scoped design should therefore be tested
with a dedicated OAuth configuration and `root_folder_id`, not assumed to be a
security boundary by itself.

`rclone mount` provides the virtual-drive behavior. Its VFS cache can use local
disk space and improves normal filesystem compatibility, but it is still a
network-backed filesystem: applications must tolerate latency, disconnects,
API quotas, and Google Workspace files that need export conversion.

`rclone bisync` provides two-way reconciliation. It is appropriate for a
controlled working tree, not for an unreviewed disaster backup: the first run
requires an explicit resynchronization, deletions propagate, and concurrent
changes need conflict policy and logs. A safer backup default is one-way
`rclone copy` or `sync` from Drive to the SSD, with a separate restore path.

## Recommended Drive design

1. Use `rclone` on PiServ with a dedicated service account or operator-owned
   OAuth token stored with root-only permissions.
2. Start with a read-only or selected-folder remote using `drive.readonly` or
   `drive.file` where it meets the use case. Use full `drive` only after the
   restore and deletion policy is agreed.
3. Mount a selected folder with a systemd user or system service only for
   workloads that need live access. Put the VFS cache on the local SSD, never
   on the remote mount itself.
4. Run a daily one-way Drive-to-SSD backup with retention, logs, health checks,
   and an explicit restore test.
5. Evaluate `bisync` separately on a small test folder. Do not enable it for the
   whole Drive until conflict, rename, deletion, Google Workspace export, and
   quota behavior are demonstrated.

## External SSD filesystems

| Filesystem | PiServ read/write | macOS read/write | Suitability |
| --- | --- | --- | --- |
| APFS | No standard, production-grade Linux read/write path in the target stack | Native | Not recommended for a disk owned by PiServ. |
| ext4 | Native and journaled | No native support | Best operational choice if the SSD stays attached to PiServ and is exposed to macOS over SMB/SFTP. |
| exFAT | Supported with Linux userspace tooling | Native | Best removable-media compromise, but no journaling, Unix permissions, or robust service-storage semantics. |
| NTFS | Read/write support exists, with more operational caveats | Read-only natively; third-party write tools | Not preferred for this workload. |

Recommendation: format the SSD as ext4 if it is a PiServ-owned backup volume.
Expose selected directories to the Mac over SMB or SFTP. Use exFAT only if the
disk must routinely be unplugged and connected directly to both systems. Do not
use APFS as the primary filesystem for Linux services; macOS support for APFS
does not imply a comparable Linux implementation.

The SSD task must include a stable UUID mount, power and USB enclosure checks,
SMART health monitoring where supported, mount options, ownership, encryption
requirements, and recovery documentation. A single local SSD is not itself a
disaster-recovery solution; the Google Drive copy and the GitHub mirror need
independent restore validation.

### External SSD implementation status

The external SSD portion was applied on 2026-07-23 after live validation:

| Item | Status | Observed result |
| --- | --- | --- |
| USB enclosure and link | Done | ASMedia ASM246X at 5 Gbps over USB 3 |
| Partition layout | Done | One GPT partition spanning 3.64 TiB |
| Filesystem | Done | Journaled ext4 labeled `external-data` |
| Mount | Done | UUID-backed `/mnt/external-data` with `nodev,nosuid` |
| Permissions | Done | `external-data` group, shared ACLs, restricted backups |
| Reboot/disconnect recovery | Pending | Validate before production backup jobs |
| Sustained backup write test | Pending | Validate with the first backup workload |

## GitHub disaster backup

The planned backup should enumerate MarcoMC-owned repositories and repositories
visible through the account's organization memberships, then maintain one bare
mirror per repository. `git clone --mirror` includes remote branches and tags;
daily `git fetch --prune` updates the mirror. Git LFS objects require a separate
`git lfs fetch --all` path. The implementation should also define whether issues,
pull requests, releases, wikis, Actions artifacts, and repository metadata are
included, because Git history alone does not capture all GitHub data.

The existing Backup CLI can be evaluated as the orchestration layer, but the
new implementation should use paginated GitHub API or `gh` discovery, a least-
privilege token, per-repository failure reporting, and a daily systemd timer.

## Jackett and torrent workload

Jackett has documented Linux ARM64 releases and recommends Docker, with the
LinuxServer.io image as the supported container path. The PiServ task should
install the existing Jackett Search CLI and its container, then validate the
API, persistent configuration, tracker setup, firewall exposure, and update
policy.

The torrent client should run as a separate container joined to a Gluetun VPN
container. Gluetun supports ARM64, has a firewall kill switch, and documents
VPN Unlimited through OpenVPN credentials; WireGuard requires the custom-provider
configuration path. The final design must validate the actual VPN Unlimited
account/configuration, LAN-only administration access, DNS behavior, torrent
traffic egress, and behavior when the tunnel is stopped. Port forwarding is a
separate capability and must not be assumed to be available from VPN Unlimited.

## Implementation gates

- Confirm the live OS, architecture, Docker, FUSE, USB enclosure, SSD health,
  and available capacity.
- Create the SSD mount and prove safe reboot, disconnect, reconnect, and
  filesystem consistency behavior before placing backups on it.
- Authenticate a restricted Drive remote and test listing, download, upload,
  rename, delete, Google Workspace export, and recovery from an interrupted
  transfer.
- Run a representative GitHub inventory and mirror test, including private
  repositories, organization repositories, pagination, tags, branches, and LFS.
- Deploy Jackett and the torrent/VPN stack only after the storage and firewall
  boundaries are in place.
- Add Ansible, systemd timers/services, runbooks, alerting, and restore tests
  after live validation.

## Sources

- [Google Drive system requirements](https://support.google.com/drive/answer/2375082/system-requirements-and-browsers-computer)
- [`rclone` Google Drive backend](https://rclone.org/drive/)
- [`rclone` mount and VFS cache](https://rclone.org/commands/rclone_mount/)
- [`rclone` bisync](https://rclone.org/bisync/)
- [Google Drive API OAuth scopes](https://developers.google.com/identity/protocols/oauth2/scopes)
- [Google Drive API scope selection](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [GitHub repository duplication and mirror clones](https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository)
- [GitHub repository API endpoints](https://docs.github.com/en/rest/repos/repos)
- [Jackett installation documentation](https://github.com/Jackett/Jackett)
- [Linux kernel filesystem documentation](https://www.kernel.org/doc/html/latest/filesystems/index.html)
- [Gluetun project](https://github.com/qdm12/gluetun)
- [Gluetun VPN Unlimited provider](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/vpn-unlimited.md)

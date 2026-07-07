# 0003: pCloud-Backed Podcast Storage

## Status

Accepted on 2026-07-07.

## Context

PiServ will run scheduled podcast-producing jobs that need their generated
audio and RSS files available through the existing podcast proxy flow.

The current operating intent is to keep podcast media in pCloud-backed storage
so generated files sync to the cloud and can be consumed by services such as
the PiGuard podcast proxy.

Official pCloud documentation reviewed on 2026-07-07:

- pCloud Drive for Linux is distributed as an AppImage and provides a desktop
  virtual drive.
- pCloud Drive's Sync feature is the official preferred path for larger
  transfers compared with direct WebDAV file operations.
- pCloud WebDAV is available for third-party tools, but pCloud documents it as
  best suited to smaller transfers and notes that large transfers may be
  interrupted.
- pCloud states that FTP and SFTP are not supported.
- pCloud states that rsync support is in development with no specific ETA.
- The pCloud download page links the official `pCloud/console-client` GitHub
  repository, which provides `pcloudcc`, a Linux console client with FUSE mount
  support.

PiServ is Debian 13 on `arm64` / `aarch64` and has FUSE support available.
PiServ is mounted in a FREENOVE FNK0100K case with a built-in touchscreen, but
the touchscreen is intended for a future purpose-built PiServ status UI rather
than for a standard Raspberry Pi desktop workflow.

## Decision

Use the official pCloud Linux console client, `pcloudcc`, as the selected
pCloud-backed storage backend for podcast media on PiServ.

Selection rationale:

- `pcloudcc` matches the server workload: a FUSE mount managed by systemd and
  validated by automation before scheduled jobs write media.
- pCloud Drive AppImage remains a possible future manual or touchscreen-facing
  tool, but it is not selected for the scheduled podcast pipeline because it is
  desktop-session oriented and not clearly documented as Debian `arm64`
  compatible.
- WebDAV remains a fallback upload/sync mechanism only if the official
  `pcloudcc` mount is not reliable enough.
- Do not depend on rsync unless pCloud releases official rsync support.

The scheduled `raiplaysound-cli` job should write into the pCloud-backed target
path only when the mount is present, writable, and passes a small write/read
verification before the job starts.

If pCloud-backed writes are not reliable, use PiServ's NVMe storage as a local
staging area and sync completed outputs to pCloud after a successful run.

## Consequences

- The pCloud mount or sync layer becomes a prerequisite for podcast-producing
  scheduled jobs.
- Automation must include explicit preflight checks for mount presence,
  writeability, and sync/mount health.
- The fallback path preserves job reliability even if pCloud is temporarily
  unavailable.
- Secrets for pCloud credentials must not be committed. Store them outside the
  repository and wire them through Ansible variables or operator-provided
  secret files.

## Follow-Up

- Identify the exact pCloud remote folder for `raiplaysound-cli` podcast media.
- Build and test `pcloudcc` on PiServ.
- Validate `pcloudcc` startup through systemd.
- Validate a write/read/delete test in the mounted target path.
- Decide whether completed media should be written directly to the pCloud mount
  or staged locally and copied after successful downloads.
- Automate the selected `pcloudcc` setup after live validation.

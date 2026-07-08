# Runbooks

## Table of Contents

- [Purpose](#purpose)
- [Index](#index)
- [Template](#template)

## Purpose

Runbooks document repeatable PiServ operations and recovery steps.

## Index

| Runbook | Purpose |
| --- | --- |
| [Server access](server-access.md) | Verify SSH and sudo access |
| [Base security hardening](base-security-hardening.md) | Track applied SSH, service, and unattended-upgrades hardening |
| [Migrate microSD to NVMe](migrate-sd-to-nvme.md) | Move the live system to NVMe boot |
| [Freenove FNK0100K post-OS](freenove-fnk0100k-post-os.md) | Configure the case after OS boot |
| [pCloud console client storage](pcloudcc-storage.md) | Validate `pcloudcc` for podcast storage |
| [RaiPlaySound CLI daily sync](raiplaysound-cli-daily-sync.md) | Operate the scheduled podcast sync |
| [System baseline and inventory](system-baseline-inventory.md) | Capture live OS, storage, network, service, and socket state |

## Template

Each runbook should include:

- Preconditions.
- Commands.
- Expected and observed results.
- Rollback or recovery notes when applicable.
- Automation follow-up when manual steps should become Ansible or shell code.

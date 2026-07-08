# Changelog

All notable changes for the pcloudcc Ansible role are documented here.

## 0.1.0 - Unreleased

### Added

- Added Galaxy-ready standalone role metadata.
- Added argument specifications for role variables.
- Added pcloudcc build dependency installation.
- Added official pCloud console-client source checkout.
- Added Debian 13 `arm64` compatibility patch for the official source.
- Added source build and `/usr/local` installation tasks.
- Added `/mnt/pcloud` mount root preparation.
- Added installed binary, shared library, and mount root validation.
- Added release runbook for exporting the role to a standalone Galaxy repo.
- Generalized role documentation so it does not depend on monorepo paths or
  host-specific assumptions.

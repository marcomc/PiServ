# Changelog

All notable changes for the putio_cli Ansible role are documented here.

## Unreleased

### Added

- Added a Galaxy-ready role that builds and installs the official putio-cli
  release on Linux ARM64 or x86_64.

### Fixed

- Preserved existing source-parent permissions, created missing parents only,
  and validated existing Node.js install-root metadata without rewriting it.

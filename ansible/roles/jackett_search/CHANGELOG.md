# Changelog

All notable changes for the jackett_search Ansible role are documented here.

## Unreleased

### Fixed

- Bind Jackett and configure its Linux Docker host gateway before its first
  upstream-managed start.
- Preserve existing source-parent ownership and permissions.
- Declare Docker Compose v2 support on Debian 13 or later and report missing
  components in check mode.

## 0.1.0 - Unreleased

### Added

- Added a Galaxy-ready role that installs jackett-search through its upstream
  Makefile.
- Added default Makefile-managed Jackett and FlareSolverr components using the
  upstream `latest` image choices.
- Added managed, create-only, and unmanaged private configuration modes.
- Added generated-Compose host binding and Linux host-gateway configuration
  without changing the upstream checkout.
- Added authenticated Jackett API validation without logging the API key.
- Added a standalone-role export and Galaxy release runbook.

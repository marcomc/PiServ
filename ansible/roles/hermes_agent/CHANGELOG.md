# Changelog

All notable changes to this role are documented here.

## [Unreleased]

- Prepared the initial `0.1.0` release candidate for standalone Ansible Galaxy
  publication after validated project use.
- Added Galaxy metadata, complete argument specifications, fixture-based
  Molecule coverage, a release runbook, and an extraction-ready CI workflow.
- Kept the role Debian ARM64, loopback-only, Codex-backed, and restricted to
  the memory and skills toolsets by default.
- Rebuild the managed dashboard terminal UI when its recorded Hermes revision
  differs from the pinned source revision, with Molecule coverage for the
  bundle and revision marker.
- Kept deployment-specific provenance plugin names and model-route
  classifications in the consuming playbook rather than role defaults.
- Kept local-model installation inert by default, gated enabled deployments on
  an active cgroup v2 memory controller, and validated bounded memory settings.

[Unreleased]: https://github.com/marcomc/ansible-hermes-agent/compare/0.1.0...HEAD

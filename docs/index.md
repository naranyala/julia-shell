# Dockyard Documentation

Dockyard is a Julia service and CLI for keeping a personal Wayland desktop
reproducible. It manages portable profile metadata, selected dotfiles, recovery
snapshots, and durable application pins. Quickshell is the presentation layer;
the Julia package remains the authority for state and mutations.

## Start here

- [Getting started](getting-started.md): install the development checkout and
  perform a safe first deployment.
- [Configuration](configuration.md): define profiles, pins, and managed files.
- [CLI reference](cli.md): commands, options, JSON output, and exit codes.
- [Architecture and protocol](architecture.md): component boundaries and the
  Unix-socket contract.
- [Safety and recovery](safety-and-recovery.md): planning, snapshots, rollback,
  path rules, and recovery procedures.
- [Development](development.md): repository layout, tests, and contribution
  workflow.
- [Compatibility and roadmap](compatibility.md): supported baseline and the
  remaining delivery work.
- [Blueprint extraction](blueprint.md): the requirements-derived architecture
  summary.

## Current status

The repository contains a tested safe-core vertical slice. Profile parsing,
path validation, deterministic planning, snapshot verification, journaled file
deployment, durable pin operations, desktop-entry resolution, JSONL transport,
and a daemon skeleton are implemented.

The real Quickshell panel, Hyprland adapter, filesystem watchers, generated
entries, archive export, retention, PackageCompiler release bundle, and full
fault-injection/recovery matrix remain tracked in [`TODOS.md`](../TODOS.md).

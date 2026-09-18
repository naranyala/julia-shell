# julia-shell documentation

julia-shell is a Julia service and CLI for keeping a personal Wayland desktop
reproducible. It manages portable profile metadata, selected dotfiles, recovery
snapshots, and durable application pins. Quickshell is the presentation layer;
the Julia package remains the authority for state and mutations.

The safe core and first desktop slice are usable from a checkout today. The
Quickshell client uses a versioned projection and the daemon has a Hyprland
adapter; watcher-driven updates and the larger desktop-environment services are
still roadmap work.

## Start here

- [Getting started](getting-started.md): install the development checkout and
  perform a safe first deployment.
- [Configuration](configuration.md): define profiles, pins, and managed files.
- [CLI reference](cli.md): commands, options, JSON output, and exit codes.
- [Architecture and protocol](architecture.md): component boundaries and the
  Unix-socket contract.
- [Runtime abstractions](runtime-abstractions.md): systemd, Wayland, and the
  provider boundaries needed by a complete shell.
- [Safety and recovery](safety-and-recovery.md): planning, snapshots, rollback,
  path rules, and recovery procedures.
- [Development](development.md): repository layout, tests, and contribution
  workflow.
- [Compatibility and roadmap](compatibility.md): supported baseline and the
  remaining delivery work.
- [Blueprint and product shape](blueprint.md): the requirements-derived
  architecture summary and future layers.

## Current status

The repository contains a tested safe-core desktop slice. Profile parsing, path
validation, deterministic planning, snapshot verification, journaled file
deployment, durable pin operations, desktop-entry resolution, compositor
projection, app actions, per-repository mutation locking, JSONL request
validation and transport, and a Quickshell bar are implemented.

Filesystem watchers, generated entries, dynamic theming, lock/idle policy,
plugins, archive validation/retention, PackageCompiler release bundle, and the
full fault-injection/recovery matrix remain tracked in [`TODOS.md`](../TODOS.md).

For the shortest path through the project, start with [Getting started](getting-started.md),
then read [Safety and recovery](safety-and-recovery.md) before changing
mutation code.

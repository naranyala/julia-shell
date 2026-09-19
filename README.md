# julia-shell

julia-shell is a Julia desktop-continuity service for portable dotfiles and durable
Wayland dock pins. Julia owns policy, persistence, revisions, snapshots, and
transactions. The CLI and Quickshell/QML layer are clients of that authority.

It is currently a safe-core desktop slice: the repository, planner, transactional
writer, pin store, JSONL daemon, compositor contract, canonical state projection,
and a multi-monitor Quickshell bar are usable. The remaining desktop-environment
layers are being added behind the same projection and IPC boundary.

## Current status

This repository is a tested safe-core vertical slice. It currently provides:

- Versioned TOML profiles with dock pins and managed file declarations.
- Strict approved-variable expansion and user-root path containment.
- Symlink-aware SHA-256 hashing for files, directories, and links.
- Deterministic plans with no-op, create, drift, conflict, excluded, missing,
  and unsafe classifications.
- Pre-change snapshots and journaled stage/commit/verify/rollback transactions.
- Durable pin, unpin, and reorder operations with repository-local revisions and
  idempotent request IDs.
- Per-repository advisory locking for serialized mutations.
- Desktop-entry scanning and explainable application identity resolution.
- A compositor-neutral model with a deterministic fake adapter and a Hyprland
  adapter for outputs, windows, focus, launch, and close operations.
- Native systemd readiness/watchdog integration, a user-session target, and a
  minimal `libwayland-client` transport binding for future generated protocols.
- One canonical state projection containing dock items, grouped running windows,
  applications, outputs, workspaces, plan health, and degraded diagnostics.
- A versioned JSONL Unix-socket daemon contract with request validation and a QML
  client that supports state reads, pin updates, focus, close, and launch.
- A multi-monitor Quickshell bar with a launcher, grouped app dock, notifications,
  MPRIS controls, system tray, battery indicator, and control center.

Filesystem watchers, archive validation, retention, PackageCompiler release
bundles, lock/idle surfaces, dynamic theming, and the full fault matrix remain
roadmap work. See [`TODOS.md`](TODOS.md) for the requirement-level backlog.

## Quick start

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
./bin/julia-shell init --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell status --repo "$HOME/.config/julia-shell/repository" --json
./bin/julia-shell plan --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --dry-run
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --yes

# Validate and install the project for the current user.
./bin/julia-shell deploy --yes

# In another terminal, start the shell daemon and Quickshell client.
./bin/julia-shelld
quickshell -p quickshell/Main.qml
```

Start with `--dry-run` and inspect the plan before applying it. Mutations that can
change live targets or pin state require explicit `--yes`. Existing targets are
snapshotted before replacement. Snapshots live under
`$XDG_STATE_HOME/julia-shell/snapshots` unless `--snapshot-root` is supplied.

## Architecture

The main flow is deliberately small:

```text
repository TOML + profile
            │
            ▼
      resolve and plan ──► plan hash / conflicts
            │
            ▼
 snapshot → stage → commit → verify
            │
            ▼
       filesystem + pins
```

The CLI and daemon share the same Julia package. `julia-shell` is the
human-facing command; `julia-shelld` is the JSONL service. The package identifier
remains `JuliaShell` because Julia module names must be valid identifiers.

## Safety model

- Paths are normalized and checked against configured allowed roots.
- Plans identify conflicts and revisions before writes begin.
- A per-repository advisory lock prevents concurrent mutations from interleaving.
- Existing files are copied into snapshots before replacement.
- Journals make interrupted transactions recoverable, and operations are designed
  to be idempotent.
- Secret-like sources require an explicit `--allow-secret` opt-in during adoption.

The current implementation is not yet a complete desktop environment: watcher
drift events, richer system controls, dynamic theming, lock/idle policy, plugins,
and stronger archive/retention policies are future work.

## Documentation

- [Documentation index](docs/index.md)
- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [CLI reference](docs/cli.md)
- [Architecture and protocol](docs/architecture.md)
- [Runtime abstractions](docs/runtime-abstractions.md)
- [Safety and recovery](docs/safety-and-recovery.md)
- [Development](docs/development.md)
- [Compatibility and roadmap](docs/compatibility.md)
- [Blueprint and product shape](docs/blueprint.md)
- [Prioritized work queue](TODOS.md)

## Project layout

- `src/`: Julia package, planner, transaction engine, protocol, and service.
- `src/DesktopEntries.jl`: reusable XDG application catalog and safe launcher
  argument handling.
- `test/`: temporary-tree unit and vertical-slice tests.
- `quickshell/`: Quickshell presentation client; it does not write profile TOML.
- `packaging/`: systemd user service template.
- `bin/`: development CLI and daemon entry points.

## Development

Run the full suite:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The runtime uses Julia standard libraries only; the separate `build/`
environment uses the external sibling [`Build.jl`](../Build.jl) target graph.
See
[`docs/development.md`](docs/development.md) for conventions and
[`docs/safety-and-recovery.md`](docs/safety-and-recovery.md) before changing
mutating code. When behavior changes, update the relevant documentation page and
the matching item in [`TODOS.md`](TODOS.md).

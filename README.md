# julia-shell

julia-shell is a Julia desktop-continuity service for portable dotfiles and durable
Wayland dock pins. Julia owns policy, persistence, revisions, snapshots, and
transactions. The CLI and Quickshell/QML layer are clients of that authority.

It is currently a safe-core vertical slice: the repository, planner, transactional
writer, pin store, and JSONL daemon are usable; the compositor and shell
integrations are still being built.

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
- A versioned JSONL Unix-socket daemon contract with request validation and a QML
  projection fixture.

The real Quickshell panel, Hyprland adapter, filesystem watchers, archive
validation, retention, PackageCompiler release bundle, and full fault matrix
are not complete. See [`TODOS.md`](TODOS.md) for the requirement-level backlog.

## Quick start

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
./bin/julia-shell init --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell status --repo "$HOME/.config/julia-shell/repository" --json
./bin/julia-shell plan --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --dry-run
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --yes
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

The current implementation is not yet a complete desktop integration: shell IPC,
compositor adapters, watchers, and stronger archive/retention policies are future
work.

## Documentation

- [Documentation index](docs/index.md)
- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [CLI reference](docs/cli.md)
- [Architecture and protocol](docs/architecture.md)
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
- `quickshell/`: presentation fixture; it does not write profile TOML.
- `packaging/`: systemd user service template.
- `bin/`: development CLI and daemon entry points.

## Development

Run the full suite:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The project intentionally uses Julia standard libraries only. See
[`docs/development.md`](docs/development.md) for conventions and
[`docs/safety-and-recovery.md`](docs/safety-and-recovery.md) before changing
mutating code. When behavior changes, update the relevant documentation page and
the matching item in [`TODOS.md`](TODOS.md).

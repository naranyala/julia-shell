# Dockyard

Dockyard is a Julia desktop-continuity service for portable dotfiles and durable
Wayland dock pins. Julia owns policy, persistence, revisions, snapshots, and
transactions. The CLI and Quickshell/QML layer are clients of that authority.

## Status

This repository is a tested safe-core vertical slice. It currently provides:

- Versioned TOML profiles with dock pins and managed file declarations.
- Strict approved-variable expansion and user-root path containment.
- Symlink-aware SHA-256 hashing for files, directories, and links.
- Deterministic plans with no-op, create, drift, conflict, excluded, missing,
  and unsafe classifications.
- Pre-change snapshots and journaled stage/commit/verify/rollback transactions.
- Durable pin, unpin, and reorder operations with repository-local revisions and
  idempotent request IDs.
- Desktop-entry scanning and explainable application identity resolution.
- A versioned JSONL Unix-socket daemon contract and a QML projection fixture.

The real Quickshell panel, Hyprland adapter, filesystem watchers, archive
validation, retention, PackageCompiler release bundle, and full fault matrix
are not complete. See [`TODOS.md`](TODOS.md) for the requirement-level backlog.

## Quick start

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
./bin/dockyard init --repo "$HOME/.config/dockyard/repository"
./bin/dockyard status --repo "$HOME/.config/dockyard/repository" --json
./bin/dockyard plan --repo "$HOME/.config/dockyard/repository"
./bin/dockyard apply --repo "$HOME/.config/dockyard/repository" --yes
```

Mutating commands require explicit `--yes`. Existing targets are snapshotted
before replacement. Snapshots live under
`$XDG_STATE_HOME/dockyard/snapshots` unless `--snapshot-root` is supplied.

## Documentation

- [Documentation index](docs/index.md)
- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [CLI reference](docs/cli.md)
- [Architecture and protocol](docs/architecture.md)
- [Safety and recovery](docs/safety-and-recovery.md)
- [Development](docs/development.md)
- [Compatibility and roadmap](docs/compatibility.md)
- [Blueprint extraction](docs/blueprint.md)
- [Remaining work](TODOS.md)

## Project layout

- `src/`: Julia package and service implementation.
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
mutating code.

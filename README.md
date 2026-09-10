# Dockyard

Dockyard is a Julia desktop-continuity service for portable dotfiles and durable
Wayland dock pins. The daemon owns state and transactions; the CLI and the
Quickshell/QML layer are clients.

## Current vertical slice

- Versioned TOML profiles with dock pins and managed file declarations.
- Strict `${HOME}` and XDG variable expansion and user-root path containment.
- Symlink-aware SHA-256 hashing for files, directories, and links.
- Deterministic plans with create, no-op, drift, conflict, excluded, missing,
  and unsafe classifications.
- Pre-change snapshots and journaled stage/commit/verify/rollback transactions.
- Durable pin, unpin, and reorder operations with revision checks and request
  idempotency.
- Desktop-entry scanning and explainable application identity resolution.
- JSONL Unix-socket daemon contract and a Quickshell state-projection fixture.

## Quick start

```sh
./bin/dockyard init --repo "$HOME/.config/dockyard/repository"
./bin/dockyard status --repo "$HOME/.config/dockyard/repository" --json
./bin/dockyard plan --repo "$HOME/.config/dockyard/repository"
./bin/dockyard apply --repo "$HOME/.config/dockyard/repository" --yes
```

Mutating commands require explicit `--yes`. Snapshots live under
`$XDG_STATE_HOME/dockyard/snapshots` unless `--snapshot-root` is supplied.
The systemd user unit is in `packaging/dockyardd.service`.

Run tests with `julia --project=. -e 'using Pkg; Pkg.test()'`.

# Getting Started

## Prerequisites

- Linux with Julia 1.9 or newer in the supported Julia 1.x range.
- A user-writable HOME and XDG directory layout.
- Quickshell and Hyprland are only required for the presentation and adapter
  work; the profile and storage core can be developed offline.

## Run from a checkout

From the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
./bin/dockyard --help
```

The entry points activate the repository project automatically. If executable
bits were not preserved by a checkout, invoke them explicitly with Julia:

```sh
julia --project=. bin/dockyard --help
julia --project=. bin/dockyardd
```

## Create a repository

Choose a location that can be version controlled. The initializer creates
`profiles/`, `files/`, and a starter profile:

```sh
./bin/dockyard init --repo "$HOME/.config/dockyard/repository"
```

The repository is portable. Do not put runtime sockets, journals, snapshots, or
machine-local state in Git unless you intentionally want diagnostic artifacts.

## Add a managed file

Place the authoritative file in the repository file tree, then add a
`[[dotfiles]]` declaration to `profiles/personal.toml`. See the complete example
in [Configuration](configuration.md).

Preview before changing the live HOME:

```sh
./bin/dockyard plan --repo "$HOME/.config/dockyard/repository"
./bin/dockyard apply --repo "$HOME/.config/dockyard/repository" --dry-run
```

Apply only after reviewing the plan:

```sh
./bin/dockyard apply --repo "$HOME/.config/dockyard/repository" --yes
```

Existing targets are snapshotted before replacement. A conflict, unsafe path,
missing source, or incomplete snapshot blocks the destructive phase.

## Manage pins

Pins use desktop-file IDs, not process IDs or compositor window addresses:

```sh
./bin/dockyard pin org.mozilla.firefox.desktop --repo "$HOME/.config/dockyard/repository" --yes
./bin/dockyard reorder 2 1 --repo "$HOME/.config/dockyard/repository" --yes
./bin/dockyard unpin org.mozilla.firefox.desktop --repo "$HOME/.config/dockyard/repository" --yes
```

Use `--json` for scripts and pass `--revision` when coordinating with another
client. A repeated `--request-id` returns the original mutation result without
writing a second revision.

## Start the daemon

The daemon listens on a per-user Unix socket. For a development session:

```sh
DOCKYARD_REPO="$HOME/.config/dockyard/repository" ./bin/dockyardd
```

For a user service, copy `packaging/dockyardd.service` to
`$HOME/.config/systemd/user/`, adjust `ExecStart` to the installed entry point,
then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now dockyardd.service
systemctl --user status dockyardd.service
```

The checked-in unit is a packaging template for the development checkout, not
an installer.

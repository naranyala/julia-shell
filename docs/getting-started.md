# Getting started

This walkthrough uses the safe-core CLI from a source checkout. It creates a
portable repository, previews a deployment, and only then changes live files.

## Prerequisites

- Linux with Julia 1.9 or newer in the supported Julia 1.x range.
- A user-writable HOME and XDG directory layout.
- Quickshell and Hyprland are only required for the presentation and adapter
  work; the profile and storage core can be developed offline.

## Run from a checkout

From the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
./bin/julia-shell --help
```

The entry points activate the repository project automatically. If executable
bits were not preserved by a checkout, invoke them explicitly with Julia:

```sh
julia --project=. bin/julia-shell --help
julia --project=. bin/julia-shelld
```

## Create a repository

Choose a location that can be version controlled. The initializer creates
`profiles/`, `files/`, and a starter profile:

```sh
./bin/julia-shell init --repo "$HOME/.config/julia-shell/repository"
```

The repository is portable. Do not put runtime sockets, journals, snapshots, or
machine-local state in Git unless you intentionally want diagnostic artifacts.

Edit `profiles/personal.toml` and place managed content below `files/`. A
minimal dotfile entry looks like this:

```toml
[[dotfiles]]
id = "shell"
source = "files/shell"
target = "${XDG_CONFIG_HOME}/shell"
mode = "copy"
platforms = ["linux"]
secret = false
```

Use [Configuration](configuration.md) for the complete schema and path rules.

## Add a managed file

Place the authoritative file in the repository file tree, then add a
`[[dotfiles]]` declaration to `profiles/personal.toml`. See the complete example
in [Configuration](configuration.md).

Preview before changing the live HOME:

```sh
./bin/julia-shell status --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell plan --repo "$HOME/.config/julia-shell/repository"
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --dry-run
```

Apply only after reviewing the plan:

```sh
./bin/julia-shell apply --repo "$HOME/.config/julia-shell/repository" --yes
```

Existing targets are snapshotted before replacement. A conflict, unsafe path,
missing source, or incomplete snapshot blocks the destructive phase.

If the plan reports `drift` or `conflict`, inspect the source, target, and
`baseline_hash` before deciding whether to update the repository or regenerate
the plan. `--force` is for a known stale-plan race; it does not bypass path or
schema validation.

## Manage pins

Pins use desktop-file IDs, not process IDs or compositor window addresses:

```sh
./bin/julia-shell pin org.mozilla.firefox.desktop --repo "$HOME/.config/julia-shell/repository" --yes
./bin/julia-shell reorder 2 1 --repo "$HOME/.config/julia-shell/repository" --yes
./bin/julia-shell unpin org.mozilla.firefox.desktop --repo "$HOME/.config/julia-shell/repository" --yes
```

Use `--json` for scripts and pass `--revision` when coordinating with another
client. A repeated `--request-id` returns the original mutation result without
writing a second revision. The same repository lock is used by CLI and daemon
mutations.

## Start the daemon

The daemon listens on a per-user Unix socket. For a development session:

```sh
JULIA_SHELL_REPO="$HOME/.config/julia-shell/repository" ./bin/julia-shelld
```

For a user service, copy `packaging/julia-shelld.service` to
`$HOME/.config/systemd/user/`, adjust `ExecStart` to the installed entry point,
then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now julia-shelld.service
systemctl --user status julia-shelld.service
```

The checked-in unit is a packaging template for the development checkout, not
an installer. Set `JULIA_SHELL_REPO` to the repository path and update the
unit's Julia and script paths before enabling it.

## Recovery locations

Snapshots, journals, revision state, and the daemon socket live outside the
repository under the XDG locations described in [Configuration](configuration.md).
If a transaction is interrupted, run `doctor` before retrying an apply and keep
the journal/backups until the affected targets have been checked.

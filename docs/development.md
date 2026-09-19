# Development

The development loop is: change the package, add focused coverage, run the
vertical suite, then update the relevant documentation and TODO status. Keep
the CLI, daemon, and QML fixture as thin clients of the same policy code.

## Repository layout

```text
Project.toml              Julia package metadata and stdlib dependencies
Manifest.toml             pinned development environment
src/JuliaShell.jl         module entry point and public API
src/Domain.jl             validated domain types
src/Config.jl             TOML schema and XDG path expansion
src/Storage.jl            hashes, atomic files, snapshots, exports
src/Reconcile.jl          planning, transactions, revisions, recovery
src/DesktopEntries.jl     XDG desktop-entry parser, index, and Exec expansion
src/Apps.jl               JuliaShell compatibility facade for DesktopEntries
src/Protocol.jl           JSONL codec and socket client helper
src/Daemon.jl             Unix-socket service loop
src/CLI.jl                command parser and renderers
quickshell/Main.qml       state-projection presentation fixture
packaging/                systemd user service template
test/runtests.jl          unit and vertical-slice acceptance coverage
```

`JuliaShell` and `src/JuliaShell.jl` are technical Julia identifiers and remain
unchanged for package validity. The user-facing brand and executable names use
`julia-shell` and `julia-shelld`.

## Test commands

Run the package suite:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run build-system targets through the separate development environment. It uses
the sibling `../Build.jl` checkout and does not become a JuliaShell runtime or
deployment dependency:

```sh
julia --project=build -e 'using Pkg; Pkg.instantiate()'
julia --project=build build.jl check
julia --project=build build.jl test
julia --project=build build.jl manifest --output /tmp/julia-shell-manifest.toml
julia --project=build build.jl verify --output /tmp/julia-shell-manifest.toml
julia --project=build build.jl clean
julia --project=build -e 'using Pkg; Pkg.test()'
```

Available targets are `all` (the default), `check`, `test`, `inventory`,
`manifest`, `verify`, `metadata`, `deploy`, and `clean`. `manifest` is a file
target that rebuilds only when its source inputs change; `verify` depends on it,
and `clean` removes it through Build.jl. Manifest output defaults to the system
temporary directory; pass `--output` to retain one elsewhere. Pass `--dry-run` to see build-graph
commands without running them. CI or a release checkout must place Build.jl at
the sibling path, or replace `build/Project.toml`'s local source with a pinned
registry or Git dependency.

Load the package without running tests:

```sh
julia --project=. -e 'using JuliaShell; println(JuliaShell.SUPPORTED_SCHEMA)'
```

The tests use temporary HOME/XDG trees and cover profile round trips, invalid
schemas, approved-root checks, variable allowlists, JSONL round trips and
request validation, safe copy deployment, baseline conflicts, snapshot
verification and restore, pin idempotency/revision conflicts, repository
locking, and desktop identity resolution.

## Implementation conventions

- Keep authoritative state in TOML and ordinary repository files.
- Use `save_toml_atomic` or `save_profile` for serialized replacements.
- Do not follow symlinks while copying snapshots.
- Validate path containment before creating staging paths.
- Acquire the repository mutation lock around profile and file writes.
- Add a deterministic unit test for every new plan classification.
- Add a fault or recovery test for every new mutating phase.
- Keep logs and errors free of managed bytes, secrets, and environment values.
- Preserve the CLI JSON envelope when changing human-readable output.

## Adding a command

Add the command to the parser and human/JSON renderers in `src/CLI.jl`, expose
the domain operation from `src/JuliaShell.jl` when it is a public API, document
the command in `docs/cli.md`, and add success plus failure tests. Commands that
can change live targets or profile/pin state must require explicit confirmation
and should return a request or transaction ID.

## Packaging status

Development uses the normal Julia project. `bin/julia-shell` and
`bin/julia-shelld` are development entry points. The systemd unit is a template;
copy it only after adjusting the checkout path. PackageCompiler relocatable
application builds, path scanning, checksums, signatures, and outside-build
verification are not implemented yet.

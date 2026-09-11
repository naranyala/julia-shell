# Configuration

A repository is portable metadata plus an authoritative `files/` tree. Choose
which profile to operate on with `--profile NAME`; the default is `personal`.
The schema is deliberately small while the compositor and shell adapters are
still under development.

## Repository layout

```text
repository/
  profiles/
    personal.toml
  files/
    ...
```

`profiles/<name>.toml` is portable metadata. `files/` contains authoritative
file and directory content. Runtime state is kept outside the repository, so a
repository can be version controlled without including sockets, journals, or
machine-local revisions.

## Profile schema

The current schema is version `1`:

```toml
schema = 1
profile = "personal"

[dock]
edge = "bottom"
output = "preferred"
autohide = "never"

[[dock.pins]]
desktop_id = "org.mozilla.firefox.desktop"
position = 10
match_app_ids = ["firefox", "org.mozilla.firefox"]
launch = "desktop-entry"
label = "Firefox"

[[dotfiles]]
id = "quickshell"
source = "files/quickshell"
target = "${XDG_CONFIG_HOME}/quickshell/julia-shell"
mode = "symlink"
platforms = ["linux"]
secret = false
```

`schema` and `profile` are required. Unknown profile fields are not currently
interpreted. A profile may contain zero or more pins and dotfile entries; entry
IDs and `(desktop_id, scope)` pairs must be unique.

## Dock fields

- `edge`: `top`, `bottom`, `left`, or `right`.
- `output`: `preferred`, `focused`, or `all`.
- `autohide`: `never`, `always`, or `intelligent`.
- `desktop_id`: the durable application identity. Keep the `.desktop` suffix.
- `position`: a non-negative stable ordering value. Pin mutations renumber the
  list in increments of ten; `reorder` uses one-based list positions.
- `match_app_ids`: optional compositor identity aliases used by the future
  adapter.
- `launch`: `desktop-entry` or `command`. The current safe core supports the
  declaration; application launching is adapter work.
- `label`: optional saved fallback label for a missing application.
- `scope`: optional scope allowing the same desktop ID in separate contexts.

## Dotfile fields

- `id`: unique logical identifier used by plans, snapshots, and restore
  selectors.
- `source`: relative path inside the repository. Source traversal outside the
  repository is rejected. The source must exist for deployment.
- `target`: absolute path or a path using the approved `HOME`/XDG variables.
- `mode`: `symlink`, `copy`, or `generated`. Generated entries are declared in
  the schema but intentionally rejected until their renderer is implemented.
- `platforms`: platform allowlist. The current target is Linux.
- `secret`: true excludes an entry from deployment planning. Secret
  synchronization is outside the MVP.
- `baseline_hash`: optional recorded source hash used to detect simultaneous
  source and target edits as a conflict. It is maintained after a successful
  deployment.

## Allowed variables and paths

Only these variables may appear in managed paths:

```text
HOME
XDG_CONFIG_HOME
XDG_DATA_HOME
XDG_STATE_HOME
XDG_CACHE_HOME
XDG_RUNTIME_DIR
```

Targets must remain under the user HOME or an XDG user directory after existing
parent symlinks are resolved. System directories, `sudo` escalation, and
unreviewed external targets are not supported. `source` paths are checked
against the repository root as well.

## Runtime locations

- `$XDG_STATE_HOME/julia-shell/snapshots/`: immutable pre-change snapshots.
- `$XDG_STATE_HOME/julia-shell/journal/`: transaction records and recovery
  markers.
- `$XDG_STATE_HOME/julia-shell/profiles/`: repository-namespaced pin revision and
  idempotency state, plus the per-repository `mutation.lock`.
- `$XDG_CACHE_HOME/julia-shell/`: reserved for rebuildable application indexes.
- `$XDG_RUNTIME_DIR/julia-shell/julia-shell.sock`: per-user daemon socket.

If an XDG variable is unset, the implementation uses the conventional HOME
subdirectory for config, data, state, and cache. The runtime fallback is a
temporary directory and should be replaced with a real user runtime directory
for a long-lived daemon.

## Practical guidance

- Keep `profiles/` and `files/` under source control, excluding host-specific
  secrets and generated artifacts.
- Prefer `${XDG_CONFIG_HOME}` or `${HOME}` in targets so the repository remains
  portable between machines.
- Use `secret = true` for entries that should stay visible in the profile but
  must be excluded from deployment. Adoption also blocks likely secret names
  unless `--allow-secret` is supplied.
- Use `--dry-run` and review `plan` classifications before the first apply.

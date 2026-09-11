# Configuration

## Repository layout

```text
repository/
  profiles/
    personal.toml
  files/
    ...
```

`profiles/<name>.toml` is portable metadata. `files/` contains authoritative
file and directory content. Runtime state is kept outside the repository.

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
target = "${XDG_CONFIG_HOME}/quickshell/dockyard"
mode = "symlink"
platforms = ["linux"]
secret = false
```

## Dock fields

- `edge`: `top`, `bottom`, `left`, or `right`.
- `output`: `preferred`, `focused`, or `all`.
- `autohide`: `never`, `always`, or `intelligent`.
- `desktop_id`: the durable application identity. Keep the `.desktop` suffix.
- `position`: a non-negative stable ordering value. Pin mutations renumber the
  list in increments of ten.
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
  repository is rejected.
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
unreviewed external targets are not supported.

## Runtime locations

- `$XDG_STATE_HOME/dockyard/snapshots/`: immutable pre-change snapshots.
- `$XDG_STATE_HOME/dockyard/journal/`: transaction records and recovery
  markers.
- `$XDG_STATE_HOME/dockyard/profiles/`: repository-namespaced pin revision and
  idempotency state.
- `$XDG_CACHE_HOME/dockyard/`: reserved for rebuildable application indexes.
- `$XDG_RUNTIME_DIR/dockyard/dockyard.sock`: per-user daemon socket.

If an XDG variable is unset, the implementation uses the conventional HOME
subdirectory. The runtime fallback is a temporary directory and should be
replaced with a real user runtime directory for a long-lived daemon.

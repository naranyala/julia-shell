# CLI reference

Run `./bin/julia-shell --help` for the command summary. Options may appear
before or after the command. `--repo PATH` and `--profile NAME` select the
repository and profile; `JULIA_SHELL_REPO` supplies the default repository.
`--json` switches the result to machine-readable JSON.

## Commands

| Command | Purpose | Effect |
| --- | --- | --- |
| `init` | Create repository skeleton and starter profile. | Repository |
| `status` | Show profile health, revision, pin count, and drift summary. | None |
| `state` | Print the canonical dock, app, output, workspace, and health projection. | None |
| `plan` | Produce deterministic proposed actions and a plan hash. | None |
| `apply` | Snapshot, stage, commit, and verify planned file changes. | Live targets + state |
| `adopt PATH` | Snapshot an existing path and import it into `files/`. | Repository + state |
| `diff [ID]` | Show plan classifications and reasons. | None |
| `pin ID` | Add a desktop-file ID to the dock. | Profile + state |
| `unpin ID` | Remove a desktop-file ID from the dock. | Profile + state |
| `reorder FROM TO` | Move one pin using one-based list positions. | Profile + state |
| `snapshot list` | List recovery snapshots. | None |
| `snapshot create` | Snapshot current targets described by the plan. | State |
| `snapshot verify PATH` | Verify snapshot manifest and payload hashes. | None |
| `restore PATH [ID...]` | Restore all or selected logical snapshot entries. | Live targets + state |
| `verify PATH` | Alias for snapshot verification. | None |
| `export PATH` | Write a portable repository directory and checksum manifest. | Destination |
| `doctor` | Check profile, paths, sources, and stale journals. | None |
| `deploy` | Validate and install the project into user-owned runtime and systemd-user locations. | User install + service files |

## Common options and safety controls

- `--yes`: required for `apply`, `adopt`, `pin`, `unpin`, `reorder`, `restore`,
  and `export`. It never infers confirmation from TTY state. `init` and
  `snapshot create` write repository/state data without this flag.
- `--dry-run`: render an `apply` plan without mutating targets.
- `--force`: permit applying a plan after its source or target changed. Prefer
  generating a new plan; use this only when the change is understood.
- `--snapshot-root PATH`: place snapshots under an explicit directory.
- `--revision N`: reject a mutation unless the current revision is `N`.
- `--request-id ID`: make a mutation idempotent across retries.
- `--position N`: insert a pin at one-based position `N`.
- `--id NAME`: logical ID used by `adopt`.
- `--target PATH`: target declaration used by `adopt`.
- `--mode copy|symlink`: adoption deployment mode.
- `--allow-secret`: explicitly override likely-secret adoption exclusion.

`deploy` requires `--yes` and stages a user-scoped install under
`$XDG_DATA_HOME/julia-shell/install` (or `~/.local/share/julia-shell/install`),
wrappers under `~/.local/bin`, and service units under
`$XDG_CONFIG_HOME/systemd/user`. It writes service files but does not enable or
start them yet; activation remains an explicit operational step.

## Plan output

JSON plan output has this shape (the action arrays contain the detailed plan):

```json
{
  "id": "transaction-independent-plan-id",
  "profile": "personal",
  "revision": 0,
  "hash": "sha256",
  "actions": [],
  "conflicts": [],
  "unsafe": [],
  "missing": []
}
```

Action kinds include `no_op`, `create`, `drift`, `conflict`, `missing_source`,
`excluded`, and `unsafe`. A plan hash is stable for the same ordered action
content; the plan ID is unique for each planning request. Use the hash and
revision as the review boundary before a later apply.

## Error output and exit codes

Errors are JSON objects on stderr with `code`, `message`, `details`, and
`remediation`. Human output is intentionally concise. The documented process
codes are:

| Code | Meaning |
| ---: | --- |
| `0` | Success. |
| `1` | General or dependency failure. |
| `2` | Usage, confirmation, or schema validation failure. |
| `3` | Unsafe or blocked plan. |
| `4` | Revision conflict. |
| `6` | Transaction failed and rolled back. |
| `7` | Recovery is required. |
| `8` | Snapshot or export integrity failure. |

The command surface will gain mandatory restore previews, bootstrap, richer
diffs, archive validation, and repair controls as tracked in [`TODOS.md`](../TODOS.md).

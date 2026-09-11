# CLI Reference

Run `./bin/dockyard --help` for the command summary. Every command accepts
`--repo PATH` and `--profile NAME`; read commands also accept `--json`.

## Commands

| Command | Purpose | Mutation |
| --- | --- | --- |
| `init` | Create repository skeleton and starter profile. | Yes |
| `status` | Show profile health, revision, pin count, and drift summary. | No |
| `plan` | Produce deterministic proposed actions and a plan hash. | No |
| `apply` | Snapshot, stage, commit, and verify planned file changes. | Yes |
| `adopt PATH` | Snapshot an existing path and import it into `files/`. | Yes |
| `diff [ID]` | Show plan classifications and reasons. | No |
| `pin ID` | Add a desktop-file ID to the dock. | Yes |
| `unpin ID` | Remove a desktop-file ID from the dock. | Yes |
| `reorder FROM TO` | Move one pin using one-based list positions. | Yes |
| `snapshot list` | List recovery snapshots. | No |
| `snapshot create` | Snapshot current targets described by the plan. | Yes |
| `snapshot verify PATH` | Verify snapshot manifest and payload hashes. | No |
| `restore PATH [ID...]` | Restore all or selected logical snapshot entries. | Yes |
| `verify PATH` | Alias for snapshot verification. | No |
| `export PATH` | Write a portable repository directory and checksum manifest. | Yes |
| `doctor` | Check profile, paths, sources, and stale journals. | No |

## Safety options

- `--yes`: required for destructive file and pin commands. It never infers
  confirmation from TTY state.
- `--dry-run`: render an apply plan without mutating targets.
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

## Plan output

JSON plan output has this shape:

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
content; the plan ID is unique for each planning request.

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
diffs, archive validation, and repair controls as tracked in `TODOS.md`.

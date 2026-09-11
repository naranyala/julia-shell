# Safety and recovery

julia-shell treats configuration writes as recoverable transactions. Preview is
the normal workflow; a destructive operation should never be the first place a
path or content problem is discovered.

## Apply pipeline

```text
resolve -> plan -> snapshot -> stage -> commit -> verify
```

1. Acquire the repository mutation lock so another writer cannot interleave
   profile or target changes.
2. Resolve expands approved variables, normalizes paths, and checks target
   parent containment.
3. Plan hashes source and target content and classifies each action.
4. Snapshot copies every existing affected target and writes a manifest before
   any live target is moved.
5. Stage writes unique sibling paths on the target filesystem.
6. Commit moves existing targets to journaled sibling backups, then moves staged
   entries into place.
7. Verify checks type, symlink destination, and content hash. Backups are
   removed only after verification.

The lock is released on both success and failure. It complements, rather than
replaces, plan revision checks and request-id idempotency.

## Plan classifications

- `no_op`: target already matches the requested deployment.
- `create`: target does not exist.
- `drift`: target differs and no simultaneous-edit conflict is known.
- `conflict`: source and target both differ from the recorded baseline.
- `missing_source`: repository source is absent.
- `excluded`: secret or platform policy excludes the entry.
- `unsafe`: source or target path violates containment policy.

Conflicts, unsafe paths, and missing sources block `apply`. Generate a fresh
plan after resolving the underlying condition. `--force` is available for a
known stale-plan race but does not bypass unsafe-path or profile validation.
The plan hash and revision are the review boundary: if either no longer matches
the intended state, inspect a new plan before applying.

## Snapshot contents

Each snapshot directory contains `snapshot.toml` and a `content/` tree. The
manifest records the logical ID, original absolute target, object type, mode,
size, SHA-256, link target when applicable, and relative payload path. The
manifest also records the operation, profile, plan hash, revision, timestamps,
and completion status.

Incomplete snapshots are never restore candidates. `verify_snapshot` checks the
manifest hash, payload hashes, relative payload paths, and symlink metadata.

## Restore procedure

List and verify a recovery point before restoring:

```sh
./bin/julia-shell snapshot list --json
./bin/julia-shell snapshot verify /path/to/snapshot --json
./bin/julia-shell restore /path/to/snapshot --repo "$HOME/.config/julia-shell/repository" --yes
```

Restore selectors use logical entry IDs. Unknown selectors fail rather than
widening the restore scope. Existing current targets are snapshotted again as
a pre-restore point. Payloads are validated before staging and targets are
checked against the same approved user-root policy as apply.

The current CLI requires `--yes` for restore; mandatory target-by-target restore
preview and archive extraction validation are tracked in [`TODOS.md`](../TODOS.md).

## Journal recovery

Journals record staging paths, target paths, backup paths, and each rename
status before the operation occurs. On daemon startup, unfinished journals are
rolled back in reverse order. Staging paths are removed when no live target was
committed; committed or target-moved steps restore their recorded backups.

Recovery is conservative: an unfinished journal is not silently discarded, and
the daemon does not accept clients until startup recovery has run.

Inspect journals when recovery reports a failure:

```sh
./bin/julia-shell doctor --repo "$HOME/.config/julia-shell/repository" --json
```

Do not delete a failed journal or its backup paths until the affected targets
have been compared with a verified snapshot.

## Symlink and secret policy

- Existing parent symlinks are resolved before target containment is accepted.
- Snapshot copy preserves symlink metadata instead of following external links.
- System paths and privilege escalation are denied in the MVP.
- Explicit secret entries are excluded from deployment.
- Adoption rejects likely secret names such as `.env`, credentials, tokens,
  passwords, and private keys unless explicitly overridden.
- Hooks, secret synchronization, and shell interpolation are not part of the
  current safe core.

# julia-shell blueprint

This page separates the product shape from the code that is already executable.
The safe core is intentionally useful without a running compositor or shell.

## Authority boundaries

- Julia owns validated profiles, revisions, application policy, snapshots, and
  transactions.
- Plain TOML and ordinary files are authoritative. Runtime state and journals
  are rebuildable operational metadata.
- QML renders a versioned projection and sends protocol requests; it does not
  write profile files.
- The CLI and daemon are both clients of the same package, so policy does not
  diverge between offline and socket-backed operation.

## Storage contract

Repositories contain `profiles/<name>.toml` and `files/...`. State is stored in
`$XDG_STATE_HOME/julia-shell`, cache data in `$XDG_CACHE_HOME/julia-shell`, and the
per-user socket in `$XDG_RUNTIME_DIR/julia-shell/julia-shell.sock`.

Every deployment follows resolve, plan, snapshot, stage, commit, and verify.
Existing targets are copied without dereferencing symlinks. Failed commits use
the journal to roll back in reverse order, and a per-repository advisory lock
prevents concurrent mutations from interleaving.

## MVP command surface

`init`, `status`, `plan`, `apply`, `adopt`, `diff`, `pin`, `unpin`, `reorder`,
`snapshot`, `restore`, `verify`, `export`, and `doctor` are exposed by the CLI.
Read output can be requested as JSON; errors contain a code, message, details,
and remediation. Unsupported or unsafe operations fail before live targets are
staged. Mutations that change live targets or pin state require `--yes`.

## Product shape still to build

The intended next layers are:

1. A real Quickshell panel and a validated direct socket integration.
2. A Hyprland adapter for window identity, focus, workspaces, and launch.
3. Watchers and event projection so external edits become visible immediately.
4. Bootstrap, overlays, richer diffs, archive validation, retention, and
   clean-home restore workflows.
5. Release packaging, signatures/checksums, accessibility, performance, and
   fault-injection gates.

The Quickshell file is intentionally a presentation fixture until the target
Quickshell version and direct socket API are confirmed on the deployment
distribution. The prioritized, requirement-level version of this list lives in
[`TODOS.md`](../TODOS.md).

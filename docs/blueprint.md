# Dockyard Blueprint Extraction

This repository implements the first vertical slice of the supplied Julia and
Quickshell blueprint.

## Authority boundaries

- Julia owns validated profiles, revisions, application policy, snapshots, and
  transactions.
- Plain TOML and ordinary files are authoritative. Runtime state and journals
  are rebuildable operational metadata.
- QML renders a versioned projection and sends protocol requests; it does not
  write profile files.

## Storage contract

Repositories contain `profiles/<name>.toml` and `files/...`. State is stored in
`$XDG_STATE_HOME/dockyard`, cache data in `$XDG_CACHE_HOME/dockyard`, and the
per-user socket in `$XDG_RUNTIME_DIR/dockyard/dockyard.sock`.

Every destructive deployment follows resolve, plan, snapshot, stage, commit,
and verify. Existing targets are copied without dereferencing symlinks. Failed
commits use the journal to roll back in reverse order.

## MVP command surface

`init`, `status`, `plan`, `apply`, `adopt`, `diff`, `pin`, `unpin`, `reorder`,
`snapshot`, `restore`, `verify`, `export`, and `doctor` are exposed by the CLI.
Read output can be requested as stable JSON; errors contain a code, message,
details, and remediation. Unsupported or unsafe operations fail before live
targets are staged.

The Quickshell file is intentionally a presentation fixture until the target
Quickshell version and direct socket API are confirmed on the deployment
distribution.

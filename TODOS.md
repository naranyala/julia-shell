# julia-shell TODOs

This list is the implementation backlog extracted from the supplied julia-shell
blueprint. The current repository is an executable safe-core vertical slice,
not a finished MVP. Items are ordered by dependency and data-safety impact.

Status markers:

- `[x]` implemented and covered by the current test suite
- `[~]` partially implemented; the remaining behavior is listed in the item
- `[ ]` not implemented

## Internal Module Plan

These are the proposed implementation boundaries for the next product layers.
The existing `Domain`, `Config`, `Storage`, and `Reconcile` modules remain the
safe-core authority; new modules should add capabilities around them rather
than duplicate their policy. A module is complete only when its public API,
failure behavior, focused tests, and CLI/protocol documentation are complete.

### Application And Desktop Runtime

- `[x]` `DesktopEntries.jl`: discover XDG applications, parse localized desktop
  metadata, expand `Exec` field codes into argv vectors, and resolve identity
  evidence. Remaining work is full desktop-entry spec coverage, icon theme
  lookup, application-index caching, invalidation, and persisted alias mapping.
- `[ ]` `Projection.jl`: build one deterministic state projection for pins,
  running applications, outputs, transactions, health, and degraded diagnostics.
  Serialize the same projection for CLI JSON, daemon responses, and QML; emit
  canonical `state.changed` topics without allowing presentation code to mutate
  authoritative state. Depends on `DesktopEntries.jl` and `Compositor.jl`.
- `[ ]` `Compositor.jl`: define compositor-neutral interfaces and data types for
  `OutputState`, `ToplevelState`, `WorkspaceState`, `WindowRef`,
  `CompositorEvent`, and `LaunchReceipt`. Include a fake implementation
  contract so projection and UI tests do not require a live desktop.
- `[ ]` `Hyprland.jl`: implement the first `Compositor.jl` adapter for outputs,
  windows, workspaces, focus, launch, open/close events, identity evidence,
  restart, reconnect, and output hotplug behavior.
- `[ ]` `DaemonWorker.jl`: move all daemon mutations behind one serialized
  worker, enforce per-connection idle timeouts, preserve request-id results,
  and provide graceful shutdown/PID lifecycle handling. The current advisory
  filesystem lock remains a cross-process safety layer, not a substitute for
  this worker.
- `[ ]` `Watchers.jl`: debounce profile and managed-target changes, recreate
  watchers after atomic replacement, run periodic hash reconciliation, and
  publish invalid-edit/degraded events while preserving the last valid revision.
  Depends on `Projection.jl` and `DaemonWorker.jl`.

### Configuration And Data Operations

- `[ ]` `Overlay.jl`: select and merge one machine overlay with explicit
  selectors, deterministic precedence, disabled entries, and the invariant
  that overlays cannot redefine secret policy. Include profile switching and
  one consolidated revision event.
- `[ ]` `Migration.jl`: migrate schema versions only after creating a snapshot,
  refuse future schemas, preserve unknown fields where supported, and expose a
  dry-run migration plan.
- `[ ]` `Generators.jl`: implement generated entries with approved variable
  interpolation, strict escaping, recorded input hashes, and no shell-code
  interpolation.
- `[ ]` `Diff.jl`: provide text, binary, symlink-target, permission, and
  target-level diffs with bounded output and no binary or secret content leaks.
  Reuse plan classifications and path policy from the safe core.
- `[ ]` `Archive.jl`: create and verify a self-contained export format; reject
  absolute paths, `..` traversal, special device nodes, unsafe symlinks, and
  invalid manifests before extraction or restore staging.
- `[ ]` `Retention.jl`: prune snapshots by count and daily/weekly tiers while
  protecting labels and guaranteeing that the newest successful snapshot is
  never removed.
- `[ ]` `Audit.jl`: append redacted request, transaction, revision, operation,
  result, and recovery records with bounded retention and no managed bytes,
  secrets, environment values, or full command lines.
- `[ ]` `Bootstrap.jl`: validate tools, source paths, target paths, desktop
  entries, profile overlays, and compositor compatibility before applying to a
  clean HOME/XDG tree. Expose a `bootstrap --profile NAME` workflow.

### Test And Release Support

- `[ ]` `FaultInjection.jl` (test support): inject failures before and after
  journal writes, snapshot writes, stages, renames, verification, and process
  boundaries. Use it for exact-old-or-exact-new recovery assertions.
- `[ ]` `RecoveryDrill.jl` (test/release support): export a reference profile,
  restore it into a clean HOME/XDG tree, and compare canonical managed-file
  hashes, symlink metadata, and pin ordering.

### Dependency Sequence

1. Build `Projection.jl` and the fake `Compositor.jl` contract around the
   existing `DesktopEntries.jl` and pin model.
2. Add `DaemonWorker.jl` and `Watchers.jl`, then expose canonical projections
   and `state.changed` events through the protocol.
3. Implement `Hyprland.jl` and replace the QML fixture with real output-aware
   behavior.
4. Add `Diff.jl`, `Overlay.jl`, `Migration.jl`, and `Generators.jl` to complete
   the configuration workflow.
5. Add `Archive.jl`, `Retention.jl`, `Audit.jl`, and `Bootstrap.jl` for the
   operations/release layer.
6. Finish `FaultInjection.jl`, `RecoveryDrill.jl`, security review, packaging,
   and performance gates before calling the desktop integration stable.

## M0: Discovery And Contracts

- `[ ]` Confirm the target distribution, Julia support range, Qt version,
  Quickshell release, Hyprland release, monitor layout, and benchmark hardware.
  Record the results in `docs/compatibility.md`.
- `[ ]` Run the real Quickshell `PanelWindow`/output prototype on Hyprland.
- `[ ]` Compare direct Quickshell socket transport with the `Process` bridge and
  pin the selected API behind contract fixtures.
- `[x]` Set the package name to `JuliaShell` with `julia-shell` as the
  display name; the repository still contains one profile tree.
- `[ ]` Define the supported Julia version range and generate a CI matrix for
  every supported architecture.
- `[ ]` Define the protocol compatibility policy for future schema versions.
- `[ ]` Define the operational lock policy for two daemon processes or two CLI
  writers targeting the same profile.

## M1: Safe Core Completion

### Configuration And Domain

- `[x]` Load and validate one versioned TOML profile with location-aware
  validation issues.
- `[~]` `Overlay.jl`: support zero or one machine overlay. Add overlay selection, merge rules,
  machine selectors, and the invariant that overlays cannot redefine secret
  policy. Covers `CORE-01` and the Machine overlay entity.
- `[x]` Serialize dock pins and dotfile declarations as portable plain files.
- `[ ]` Add unknown-field warnings for compatible minor schema versions and
  hard failures for incompatible major versions.
- `[ ]` `Migration.jl`: add schema migration commands. A migration must create a snapshot first
  and refuse to rewrite a future schema.
- `[ ]` Add `Overlay.jl` profile switching through the transaction planner and emit one
  consolidated revision event.

### Paths, Hashes, And Planning

- `[x]` Expand only the approved `HOME` and XDG variables.
- `[x]` Resolve target parents and reject paths escaping approved user roots.
- `[x]` Hash files, directories, and symlinks without dereferencing symlink
  targets during snapshot copy.
- `[~]` Plan classifies no-op, create, drift, conflict, missing source,
  excluded, and unsafe entries. Add an explicit delete classification and
  support an owned-target deletion policy.
- `[~]` Conflict detection uses the optional recorded baseline hash. Add
  baseline recording for all deployment modes and tests for an external edit
  between plan and commit.
- `[ ]` Add profile-wide and entry-local ignore rules plus `doctor`/`explain`
  output for every ignored path.
- `[ ]` `Generators.jl`: implement generated entries with approved variable interpolation,
  strict escaping, and recorded input hashes. Never interpolate shell code.

### Transactions And Recovery

- `[x]` Apply follows resolve, plan, snapshot, stage, commit, and verify.
- `[x]` Existing targets are snapshotted before replacement.
- `[x]` Staging and rollback paths are recorded in a journal before renames.
- `[x]` Verification checks the resulting type/link target/content hash.
- `[x]` Failed in-process transactions roll back committed steps in reverse
  order.
- `[x]` Daemon startup can recover incomplete journals by removing owned staging
  paths or restoring recorded backups.
- `[ ]` `FaultInjection.jl`: add hooks before and after every stage, rename, journal
  write, snapshot write, and verification step.
- `[ ]` `RecoveryDrill.jl`: add process-kill tests for every transaction phase, including a kill
  between target rename and staged rename. Acceptance target: either exact old
  state or exact new state is recoverable, never an untracked mixture.
- `[~]` Add filesystem locking around repository mutations; `DaemonWorker.jl`
  must add a single daemon mutation worker so concurrent CLI and daemon writes cannot race
  profile or revision state.
- `[ ]` Add fsync of staged files, parent directories, journal records, and the
  final atomic replacement where the platform supports it.
- `[ ]` Make snapshot storage-full and permission failures block destructive
  changes before the first live-target mutation.

## M2: Application Model And Daemon

### Desktop Entries And Resolution

- `[x]` Scan XDG desktop-entry directories and expose names, icons,
  `StartupWMClass`, and executable basenames.
- `[x]` Resolve exact desktop IDs, startup classes, normalized app IDs,
  executable basenames, aliases, scores, and ambiguity status.
- `[x]` Preserve missing pinned desktop IDs instead of silently deleting them.
- `[~]` `DesktopEntries.jl` parses desktop-entry `Exec` with quote, escape, and field-code handling;
  complete spec coverage and validation remain. Never concatenate an Exec value
  into a shell command.
- `[ ]` Extend `DesktopEntries.jl` with icon theme lookup, absolute icon handling,
  and a generic fallback.
- `[ ]` Extend `DesktopEntries.jl` to cache the application index under `$XDG_CACHE_HOME/julia-shell` and
  invalidate it when application directories change.
- `[ ]` Extend `DesktopEntries.jl` with a user-facing mapping command that persists an alias only after an
  ambiguous candidate is explicitly selected.

### Compositor Adapter

- `[ ]` `Compositor.jl`: define `AbstractCompositor`, `OutputState`, `ToplevelState`,
  `WindowRef`, `CompositorEvent`, and `LaunchReceipt` interfaces.
- `[ ]` `Hyprland.jl`: implement the Hyprland adapter for outputs, toplevels, workspaces,
  focus, launch, open/close, and identity evidence.
- `[ ]` Add bounded reconnect backoff and degraded status on adapter disconnect.
- `[ ]` `Compositor.jl`: add a fake adapter that replays deterministic fixtures for core and UI
  tests.
- `[ ]` Add Hyprland restart and output hotplug fixtures.

### Daemon And Protocol

- `[x]` Provide versioned newline-delimited JSON envelopes with a bounded
  message size and request/response helpers over a Unix socket.
- `[x]` Restrict the runtime directory and socket permissions to the user.
- `[~]` Serve status, plan, and pin mutations over the socket. `Projection.jl` must add a canonical
  state projection, `state.changed` events, subscription handling, and
  per-connection idle timeouts.
- `[~]` Pin mutations enforce revisions and bounded idempotency keys. `DaemonWorker.jl` must move all
  mutations behind a serialized queue and return the original response for a
  repeated request ID.
- `[ ]` Validate peer ownership where the host exposes Unix-socket credentials.
- `[ ]` Publish health, active profile, revision, compositor, last transaction,
  and degraded diagnostics through both CLI and protocol.
- `[~]` Add request schema validation and explicit error envelopes; add protocol
  version negotiation and contract fixtures shared by Julia and QML.
- `[ ]` `Watchers.jl`: add debounced profile watching, watcher recreation after atomic rename,
  periodic hash reconciliation, and invalid-edit error events that preserve the
  last valid revision.
- `[ ]` `DaemonWorker.jl`: add graceful daemon shutdown and PID/lock lifecycle handling.

## M3: Dock Vertical Slice

### Durable Pin Behavior

- `[x]` Persist pin, unpin, and reorder operations atomically in the profile with
  a revision counter.
- `[x]` Reject duplicate pins and stale revisions with machine-readable errors.
- `[ ]` `Projection.jl`: merge pinned applications with normalized running-unpinned toplevels in
  one stable projection.
- `[ ]` Implement absent-app launch, one-instance focus/workspace switching,
  and multiple-instance cycling.
- `[ ]` Implement context actions for new instance, pin/unpin, close, details,
  and adjacent-output movement where supported.
- `[ ]` Add per-output policies: preferred, focused, named, and all.
- `[ ]` Add autohide policies: never, always, intelligent, with configurable
  reveal delay.
- `[ ]` Support keyboard focus, modifier+arrow reorder, delete confirmation or
  undo toast, and accessible announcements.

### Quickshell Presentation

- `[~]` Keep the `Projection.jl` QML state-projection fixture that renders malformed items as
  placeholders and exposes accessible names. Replace the fixture with a real
  Quickshell shell after the M0 transport spike.
- `[ ]` Implement one compositor-aware `PanelWindow` per selected output.
- `[ ]` Reserve exclusive zone only when configured and handle scale changes,
  output disconnect/reconnect, and duplicate-surface prevention.
- `[ ]` Implement direct socket or bridge transport without allowing QML to edit
  profile TOML.
- `[ ]` Add optimistic pin/reorder updates that reconcile to a daemon revision
  or visibly revert within one second.
- `[ ]` Add theme tokens for size, radius, spacing, opacity, color, animation,
  and reduced-motion behavior.
- `[ ]` Add visible non-color-only indicators for running, focused, urgent,
  missing, disconnected, stale, and error states.
- `[ ]` Add model, interaction, screenshot, output-hotplug, scale, missing-icon,
  malformed-item, and service-loss UI tests.

## M4: Dotfiles Workflow

- `[x]` Support file and directory deployment in symlink and copy modes.
- `[x]` Provide `init`, `status`, `plan`, `apply`, `adopt`, `diff`, `pin`,
  `unpin`, `reorder`, `snapshot`, `restore`, `verify`, `export`, and `doctor`
  command entry points.
- `[~]` `adopt` snapshots the target and imports it into `files/`. Add a
  mandatory preview showing source, destination, target, policy decision, and
  snapshot before the import.
- `[ ]` `Diff.jl`: add text diff output, symlink-target diff, permission diff, and concise
  binary summaries without printing binary contents.
- `[ ]` `Bootstrap.jl`: add a `bootstrap --profile NAME` command that validates tools, source
  paths, target paths, desktop entries, and compositor compatibility before
  applying.
- `[ ]` Make every mutating command require explicit confirmation or an
  exported/printed plan. `snapshot create` currently needs the same CLI guard.
- `[ ]` Add clean-home integration coverage for first apply, drift, conflict,
  partial restore, restart, watcher reattach, and rollback.
- `[ ]` Add profile overlays for host-specific paths and disabled entries.
- `[ ]` `Audit.jl`: add audit history with request ID, transaction ID, revision, operation,
  result, and redacted diagnostics.

## M5: Backup And Operations Release

### Snapshots, Export, And Restore

- `[x]` Generate sortable unique snapshot IDs and immutable completed snapshot
  manifests.
- `[x]` Verify manifest and payload hashes before restore staging.
- `[x]` Restore selected logical IDs and create a pre-restore snapshot.
- `[~]` `Archive.jl`: export creates a self-contained directory and checksum manifest. Add a
  verified archive format and reject absolute paths, `..` traversal, special
  device nodes, and unsafe symlink extraction before staging.
- `[~]` Restore currently requires `--yes` but does not first print a complete
  target-by-target restore plan. Add mandatory preview and exported plan hash.
- `[ ]` `RecoveryDrill.jl`: export a reference profile, restore into
  a fresh HOME/XDG tree, and compare canonical managed-file hashes and pin
  ordering.
- `[ ]` `Retention.jl`: implement retention by count, daily/weekly tiers, protected labels, and
  the invariant that the newest successful snapshot is never pruned.
- `[ ]` Add `doctor --repair` only for explicitly safe repairs and report
  unbacked portable files, incomplete snapshots, stale journals, permissions,
  missing tools, missing desktop IDs, and socket problems.
- `[ ]` `Archive.jl`: add export verification independent of the source repository and a
  checksum/signature release manifest.

### Packaging And Startup

- `[x]` Provide a systemd user service unit and manual Julia entry points.
- `[ ]` Add install/uninstall documentation for the systemd user unit, logs,
  environment overrides, repository selection, and manual startup.
- `[ ]` Add a pinned PackageCompiler build entry point for each supported
  architecture.
- `[ ]` Execute the packaged daemon outside the build directory and scan the
  bundle for build paths, absolute secrets, and confidential preferences.
- `[ ]` Add checksum generation and signing to the release pipeline before
  calling an artifact stable.

## M6: Hardening And Release Gates

### Security And Privacy

- `[x]` Deny system targets in the MVP and enforce approved user-root
  containment.
- `[x]` Exclude explicitly marked secrets and common likely-secret names from
  adoption by default.
- `[~]` Symlink-safe local snapshot copying is implemented. Add adversarial
  tests for symlink parents, dangling links, rename races, and repository links.
- `[ ]` `Archive.jl`: add archive extraction validation for path traversal, absolute paths,
  device nodes, and unsafe links.
- `[ ]` `Audit.jl`: add redacted structured logs; never log managed bytes, secret values,
  environment values, or full command-line contents.
- `[ ]` If hooks are introduced, keep them disabled by default and enforce an
  executable allowlist, timeout, minimized environment, captured output, and
  recorded exit status. Otherwise keep hooks explicitly out of the MVP.
- `[ ]` Threat-model malicious profile repositories and malformed desktop files.

### Reliability And Performance

- `[ ]` Add deterministic property tests for generated profiles, filesystem
  trees, ordering, idempotency, path containment, and snapshot invariants.
- `[ ]` Add disk-full, permission, interrupted-write, malformed-profile, and
  malformed-protocol fault tests.
- `[ ]` Benchmark 1,000 pin/reorder socket round trips and publish p95 latency.
- `[ ]` Measure dock input response at p95 <= 50 ms.
- `[ ]` Measure pin/reorder persistence acknowledgement at p95 <= 150 ms.
- `[ ]` Measure daemon idle CPU <= 0.5% over 10 minutes.
- `[ ]` Measure combined idle RSS <= 220 MiB and daemon RSS <= 110 MiB.
- `[ ]` Measure packaged daemon readiness <= 1.5 s and hot CLI status <= 250 ms.
- `[ ]` Scale-test 200 pins/entries and 2,000 snapshots without O(n) work on
  every UI event.
- `[ ]` Reduce dependencies and precompile the resident daemon path before
  relaxing any missed performance budget.

### Acceptance Scenarios

- `[x]` AC-02 duplicate reorder request returns the original result in the
  current pin mutation API.
- `[x]` AC-03 source/target baseline conflict blocks apply without mutation.
- `[x]` AC-05 missing applications remain stored pins; desktop index resolution
  reports a missing status.
- `[x]` AC-06-equivalent local snapshot payload traversal is rejected by
  snapshot verification. Add an archive-specific test when archives exist.
- `[~]` AC-01 persisted reorder exists, but the Quickshell/compositor restart
  flow is not implemented.
- `[~]` AC-04 rollback and startup recovery exist; add injected process-kill
  coverage after each of three renames.
- `[~]` AC-07 invalid profile parsing preserves the old on-disk revision, but a
  watcher event and location-aware daemon event are not implemented.
- `[ ]` AC-08 output disconnect/reconnect at a new scale results in exactly one
  dock surface.
- `[x]` AC-09 snapshot failure occurs before target staging; add an explicit
  full-filesystem simulation.
- `[ ]` AC-10 exported backup restores canonical hashes and desktop IDs in a
  clean home.

## Definition Of Done For New Mutating Features

- `[ ]` Document human and JSON plan output and its schema.
- `[ ]` Test success, validation failure, stale revision, permission failure,
  disk-full, interrupted-write, and recovery behavior.
- `[ ]` Define and test snapshot, rollback, and journal semantics.
- `[ ]` Include transaction/request IDs in redacted logs.
- `[ ]` Include a user-facing recovery action that states what changed and what
  was not changed.
- `[ ]` Keep the clean-home recovery suite passing.

## MVP Ship Checklist

- `[ ]` Every Must requirement is implemented or removed by a reviewed scope
  change.
- `[ ]` Fault-injection and clean-home recovery gates pass with no unresolved
  data-loss or path-escape defects.
- `[ ]` Pin, unpin, reorder, missing app, Quickshell restart, compositor restart,
  and machine restore pass.
- `[ ]` Reference performance results and approved exceptions are published.
- `[ ]` Release bundle runs outside its build path and has checksums/signature.
- `[ ]` Systemd install/uninstall, logs, doctor, manual startup, backup, and
  restore documentation are verified by a second tester.
- `[ ]` Supported Julia, Quickshell, Qt, Hyprland, and distribution versions are
  recorded.
- `[ ]` A second tester completes bootstrap and restore using only published
  documentation.

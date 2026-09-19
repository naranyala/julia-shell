# julia-shell TODOs

This list is the implementation backlog extracted from the supplied julia-shell
blueprint. The current repository is an executable safe-core vertical slice,
not a finished MVP. Items are ordered by dependency and data-safety impact.

Status markers:

- `[x]` implemented and covered by the current test suite
- `[~]` partially implemented; the remaining behavior is listed in the item
- `[ ]` not implemented

## Pyramid-of-intents gap register

`PYRAMID-OF-INTENTS.md` describes the dependency structure that the product
must preserve. This register tracks the work still required to make that
structure complete. Labels identify the kind of work:

- **Feature** — user-visible behavior or operational capability.
- **Abstraction** — a policy, contract, provider, or boundary needed to keep
  the system coherent as capabilities grow.
- **Integration** — validation or implementation against an external desktop
  component, protocol, service, distribution, or release environment.
- **Test** — missing test coverage for an existing or new capability.

Items marked with `[P]` are directly called out as structural gaps in
`PYRAMID-OF-INTENTS.md`.

### Foundation: authority, determinism, least authority, observability

- [ ] **Abstraction — schema evolution:** define compatibility policy for
  profile, projection, and JSONL protocol versions; warn on compatible unknown
  fields, reject incompatible/future schemas, and provide dry-run migrations.
- [ ] **Abstraction — one mutation authority:** add a serialized daemon worker,
  graceful shutdown/PID lifecycle, per-connection idle limits, and explicit
  ownership when CLI and daemon writers overlap. The filesystem lock remains a
  safety backstop, not the worker model.
- [ ] **Feature — complete auditability:** append bounded, redacted records for
  requests, plans, revisions, transactions, recovery, and provider failures;
  never record managed bytes, secrets, environment values, or full commands.
- [ ] **Feature — external-drift visibility:** add debounced profile/target
  watchers, periodic hash reconciliation, watcher recreation after atomic
  replacement, and invalid-edit events that preserve the last valid revision.
- [ ] **Feature — deterministic fault proof:** add fault injection at every
  journal, snapshot, stage, rename, verify, and process boundary, plus
  process-kill recovery drills proving exact-old-or-exact-new state.
- [ ] **Feature — durability hardening:** fsync staged files, parent
  directories, journals, and final replacements where supported; preflight
  storage-full and permission failures before the first destructive mutation.
- [P] [ ] **Test — daemon socket integration:** start a real daemon process,
  connect via Unix socket, round-trip `status`, `plan`, `state.get`,
  `pins.pin`, `pins.unpin`, `pins.reorder`, and `apps.launch`/`focus`/`close`
  methods, and verify `state.changed` event emission after pin mutations.
  Currently only `_daemon_dispatch` for `state.get` is unit-tested.
- [P] [x] **Test — journal recovery:** write a mid-transaction journal, corrupt
  or leave it incomplete, start the daemon, and verify `recover_journals!`
  restores exact-old or exact-new state. No test currently exercises
  `recover_journals!`.
- [P] [x] **Test — unpin coverage:** add a test for `unpin!` with idempotent
  request IDs, revision tracking, and missing-pin error handling. Only `pin!`
  and `reorder!` are currently tested.

### Authority and safe configuration delivery

- [ ] **Feature — machine overlays:** select and merge zero or one explicit
  machine overlay with deterministic precedence, disabled entries, profile
  switching, and one consolidated revision event; overlays must not redefine
  secret policy.
- [ ] **Feature — generated configuration:** implement approved-variable,
  strictly escaped generators with recorded input hashes; never interpolate
  shell code. The `generated` mode is accepted by the schema but throws
  `JuliaShellError(:unsupported_mode, ...)` at staging time in `Reconcile.jl:180`.
- [ ] **Feature — explainable diffs and ignores:** add text/binary/symlink/
  permission/target diffs with bounded, secret-safe output, plus profile and
  entry ignore rules and `doctor` explanations for every ignored path.
- [ ] **Feature — safe portable archives:** define a self-contained export
  manifest and verify before extraction; reject absolute paths, traversal,
  unsafe symlinks, special files, invalid manifests, and secret leakage.
- [ ] **Feature — retention and clean-home recovery:** implement count and
  daily/weekly retention tiers while protecting labels and the newest good
  snapshot; add bootstrap and recovery-drill workflows for a clean HOME/XDG
  tree.
- [ ] **Abstraction — owned-target policy:** define explicit delete semantics,
  ownership markers, and baseline recording for every deployment mode before
  adding destructive or cleanup operations.

### Desktop understanding and durable identity

- [~] **Feature — complete desktop-entry behavior:** finish specification
  coverage, validation, icon-theme lookup, absolute-icon handling, generic
  fallback, application-index caching, directory invalidation, and an
  explicit ambiguous-alias mapping command. Safe absolute/theme/pixmap icon
  resolution is now implemented; full spec coverage, caching, invalidation,
  and alias persistence remain.
- [ ] **Abstraction — identity lifecycle:** persist user-selected aliases and
  identity evidence separately from durable pins; define how renamed,
  missing, duplicate, and ambiguous applications are represented across
  revisions.
- [ ] **Integration — desktop catalog reality:** test precedence and identity
  resolution against the target distribution's XDG application directories,
  locale behavior, desktop-file updates, and actual launcher conventions.

### Desktop interaction and canonical projection

- [~] **Feature — dedicated statusbar contract:** expose a versioned
  Julia-owned `statusbar` projection containing health, degraded diagnostics,
  profile/revision, compositor, outputs, workspaces, pinned/running/focused/
  urgent counts, and bind a compact QML indicator. Provider-backed network,
  audio, power, media, notification, and connectivity segments still need
  real runtime providers and action contracts.
- [ ] **Feature — complete dock semantics:** named-output policy, autohide
  modes/reveal delay, workspace-aware launch/focus routing, multiple-instance
  cycling, adjacent-output movement, details actions, keyboard reorder,
  delete confirmation/undo, and accessible announcements.
- [~] **Abstraction — canonical event stream:** extend projection beyond
  bounded polling with subscriptions, monotonic event/revision semantics,
  stale-event handling, and a single state/event source shared by CLI, daemon,
  and QML. Runtime/provider callback subscriptions are now available; daemon
  projection subscriptions and revision ordering remain.
- [ ] **Feature — optimistic UI reconciliation:** allow pin/reorder optimism
  only with daemon revision confirmation or a visible revert within one second.
- [P] [x] **Feature — QML state.changed event handling:** the Quickshell client
  receives `state.changed` events from the daemon but discards them
  (`Main.qml:84-86: return`). Replace the 4-second polling loop with
  event-driven projection updates using the revision and topics from the event.
- [P] [x] **Feature — QML autohide projection binding:** the `autohide` property
  in `Main.qml:25` is hardcoded to `"never"`. Bind it to
  `projection.dock.autohide` from the live daemon projection so autohide
  policies take effect in the UI.
- [ ] **Integration — Quickshell/Qt:** validate the checked-in Quickshell
  0.3.1 client on the supported distribution and Qt version; confirm
  `PanelWindow`, output lifecycle, socket transport, scaling, exclusive zones,
  output hotplug, duplicate-surface prevention, malformed-item rendering,
  screenshots, and reduced-motion behavior.
- [ ] **Integration — accessibility/performance:** test keyboard-only use,
  focus semantics, AT-SPI announcements, contrast, reduced motion, startup
  latency, projection refresh cost, and multi-monitor resource use.

### Platform and provider boundaries

- [~] **Abstraction — provider completeness:** implement the common
  `capabilities`, `snapshot`, `subscribe`, `invoke`, and `health` contract for
  real providers, including bounded state, restart generations, timeouts, and
  deterministic fakes. Callback subscription is now covered by the fake;
  provider implementations and lifecycle hardening remain.
- [ ] **Feature — session coordination:** wire provider health, startup order,
  degraded aggregation, restart policy, and one canonical provider event
  stream into the daemon projection.
- [ ] **Integration — Hyprland:** finish event-socket handling, reconnect
  backoff, restart recovery, output hotplug, workspace events, and fixtures
  against the supported Hyprland release.
- [ ] **Integration — Wayland protocols:** add registry discovery, generated
  XML bindings, queue ownership, reconnect behavior, and fake-display tests;
  implement capability-isolated surface, toplevel, workspace, output, seat,
  session-lock/idle, clipboard, capture, and activation providers.
- [ ] **Integration — systemd user session:** validate notify/watchdog,
  environment import, target ordering, service restart behavior, executable
  substitution, and independent scope-based application launching on the
  target distribution.
- [ ] **Abstraction — application launcher:** move launch ownership out of the
  compositor interface into a provider that supports desktop entries,
  activation tokens, independent systemd scopes, lifecycle events, and safe
  argv handling.
- [ ] **Feature — desktop service providers:** add explicit degraded-capable
  Notification, Audio/PipeWire, NetworkManager, Bluetooth/BlueZ, Power/UPower,
  Media/MPRIS, Appearance, Secret, Portal, and Accessibility providers, each
  with an in-memory fake and no credentials in projections or logs.
- [ ] **Abstraction — extension isolation:** add a capability-scoped plugin host
  with timeouts, bounded output/state, and no implicit filesystem, process, or
  network authority.

### Release and trust boundary

- [ ] **Integration — supported matrix:** record and continuously test the
  supported Linux distribution, Julia range/architectures, Qt, Quickshell,
  Hyprland, Wayland libraries, systemd, monitor layouts, and benchmark
  hardware; do not infer desktop support from a passing core suite.
- [ ] **Feature — release artifacts:** produce PackageCompiler bundles,
  checksums/signatures, install/uninstall helpers, service setup, and upgrade
  compatibility checks without placing runtime state in the repository.
- [ ] **Feature — second-person recovery gate:** have an independent operator
  export, restore into a clean tree, compare canonical hashes/symlink metadata
  and pin ordering, and sign off the fault matrix before calling desktop
  integration stable.

### Dependency order for closing the pyramid

1. Complete schema/version policy, daemon worker, watchers, audit, fault
   recovery, and the three missing test suites (daemon socket integration,
   journal recovery, unpin coverage) so the authority layer remains singular,
   observable, and verified.
2. Finish overlays, migrations, generators, diffs, archive validation,
   retention, bootstrap, and ownership/delete semantics for configuration
   continuity.
3. Harden desktop identity, canonical subscriptions, dock semantics, optimistic
   reconciliation, and the two QML structural gaps (state.changed event
   handling, autohide projection binding).
4. Complete provider contracts and wire real Hyprland, Wayland, systemd, and
   desktop-service integrations with degraded behavior and fakes.
5. Validate Quickshell/Qt and accessibility/performance on the supported
   matrix, then build release artifacts and pass the recovery gate.

No upper-layer feature should introduce a second persistence model, bypass the
Julia policy boundary, or depend on an untested live desktop mechanism.

## Internal library-shaped modules

These are deliberately **internal Julia modules**, not external packages yet.
They should have narrow APIs and package-quality tests so they can later be
extracted without redesigning JuliaShell's product policy. None may create a
second persistence authority.

### `BuildValidation.jl` (internal validation and release utility boundary)

Purpose: make repository validation and release preparation deterministic,
inspectable, and independent of the runtime daemon. `BuildValidation.jl` is a validation
utility module, not a second application entry point or runtime configuration
store.

- [x] Add standalone `BuildValidation.jl` APIs for project-root discovery, sorted source
  inventory, structural repository checks, and build reports.
- [x] Add deterministic artifact manifests containing project identity, file
  sizes, and SHA-256 hashes; write them atomically and verify them before
  release/archive work.
- [x] Add a root `build.jl` command entry point with `check`, `inventory`,
  `manifest`, and `verify` commands plus `--root`/`--output` options.
- [~] Add Julia source loading/parse checks, exported-symbol checks, and
  profile/schema/protocol fixture validation to `build check` without starting
  a daemon or requiring a compositor. Source parsing, exported-symbol checks,
  and TOML fixture checks are implemented; domain-specific fixture checks remain.
- [~] Add generated release metadata (supported Julia/Qt/Quickshell/Hyprland
  matrix, git revision, platform, and build inputs) without embedding secrets
  or mutable runtime state. Project version, Julia/platform information, and
  git revision are implemented; compatibility-matrix metadata remains.
- [ ] Add reproducible PackageCompiler bundle orchestration, checksums and
  signatures, staging-directory cleanup, and upgrade compatibility checks.
- [ ] Add archive/export validation through the same manifest and path-safety
  rules; fail before producing a release artifact when a required input is
  missing or changed.
- [~] Add CI-friendly exit codes, machine-readable JSON reports, and a
  no-network mode; external tools must be detected and reported rather than
  silently assumed. JSON output and read-only/no-network behavior are
  implemented; broader external-tool detection remains.
- [ ] Keep build outputs outside the repository by default, except for an
  explicitly requested manifest path, and add tests for dirty/partial trees.

### `Deploy.jl` (user-serving installation boundary)

Purpose: install a validated JuliaShell checkout into user-owned runtime
locations and register the daemon/UI services without requiring root access or
turning the repository into a mutable install directory.

- [x] Add a deployment plan with explicit install, bin, systemd-user, and
  repository paths derived from HOME/XDG variables.
- [x] Validate the source with `BuildValidation.validate_repository` before copying;
  stage the install tree and generate absolute-path Julia wrappers for the CLI
  and daemon.
- [x] Install service templates for the daemon, UI, and user target with the
  deployed paths and repository environment substituted.
- [x] Add a root `deploy` CLI command requiring explicit `--yes` confirmation.
- [x] Preserve the previous install tree during replacement and restore it if
  staged installation fails.
- [ ] Add an explicit `systemctl --user daemon-reload`, enable/start/stop
  policy, and dry-run plan output; service activation must remain opt-in and
  must never happen merely because files were installed.
- [ ] Add install ownership manifests and an uninstall/upgrade command that
  removes only files previously owned by this deployment.
- [ ] Add preflight checks for Julia version, Quickshell availability, target
  compositor, writable XDG paths, socket path length, and service command
  availability; report degraded optional integrations clearly.
- [ ] Add post-install health checks for wrapper startup, daemon readiness,
  socket permissions, journal recovery, and QML/service configuration.
- [ ] Add a clean-user-tree deployment test and a second-person upgrade/
  rollback drill before declaring system serving stable.

**Extraction readiness:**

- [x] Project-root discovery, source inventory, structural checks, and
  manifest generation have no julia-shell domain dependencies.
- [x] Deterministic artifact manifests with SHA-256 hashes are self-contained.
- [x] Failure types defined locally; no `JuliaShellError` dependency.
- [x] Standalone test suite exercises syntax checks, inventory, manifest, and verify
  without JuliaShell module.
- [ ] Documented as a general-purpose build validation toolkit.

### `DesktopCatalog.jl` (library-shaped desktop-entry boundary)

Purpose: provide a complete, reusable application catalog to the projection,
launcher, and compositor identity code while keeping XDG details out of the
rest of the product.

- [~] Move the remaining `DesktopEntries.jl` responsibilities behind a stable
  catalog API: parse, discover, localize, validate, resolve identity, expand
  safe argv, and resolve icons. The current parser, discovery, identity
  scoring, and icon lookup are the first implementation.
- [x] Define explicit value types for `ApplicationCatalog`, `IdentityEvidence`,
  and `IconResolution`; do not expose mutable parser internals.
- [ ] Add application-index caching under `$XDG_CACHE_HOME/julia-shell`, with
  source-directory signatures, invalidation after desktop-file changes, and a
  cache rebuild when the manifest is corrupt or stale.
- [ ] Finish desktop-entry specification coverage and malformed-entry
  diagnostics; preserve user-directory precedence and hidden-entry policy.
- [ ] Add persisted alias mapping only after an ambiguous candidate is
  explicitly selected; aliases must be revisioned and auditable.
- [ ] Test the module independently with temporary XDG trees, locales,
  duplicate IDs, missing entries, unsafe `Exec` values, icon themes, and
  cache invalidation.

**Extraction readiness:**

- [x] Zero imports from Domain, Config, Storage, Reconcile, Projection,
  Daemon, or CLI.
- [x] Public API documented with docstrings for every exported symbol.
- [x] Failure types defined locally (no `JuliaShellError` dependency).
- [ ] Standalone test suite passes without loading JuliaShell module.
- [ ] At least one consumer outside DesktopEntries call sites demonstrates
  the API works independently.

### `TransactionalFS.jl` (library-shaped safe filesystem engine)

Purpose: isolate generic, recoverable file deployment from JuliaShell profile
policy. This module owns mechanics; `Config.jl` and `Reconcile.jl` continue to
own profile semantics and plan policy until the boundary is proven.

- [ ] Define generic `FileOperation`, `FilePlan`, `SnapshotManifest`, and
  `TransactionJournal` types that do not depend on `Profile`, `Pin`, or dock
  concepts.
- [ ] Move or wrap path containment, symlink-aware inspection/hashing, atomic
  copy/symlink staging, snapshot creation/verification, journal writes,
  rollback, and startup recovery behind that API.
- [ ] Add explicit operation ownership and delete policy before exposing
  destructive operations; reject unowned deletes by default.
- [ ] Add durability hooks for fsync, storage-full preflight, permission
  checks, and fault injection at every externally visible phase.
- [ ] Guarantee exact-old-or-exact-new recovery under process termination;
  include kill tests between target rename and staged rename.
- [ ] Keep the current CLI/projection error codes stable through an adapter
  layer and document which errors are safe to retry.
- [ ] Test this module without loading desktop, Wayland, Quickshell, or systemd
  integrations.

**Extraction readiness:**

- [ ] Generic types (`FileOperation`, `FilePlan`, `SnapshotManifest`,
  `TransactionJournal`) have no julia-shell domain dependencies.
- [ ] Path containment, hashing, staging, snapshot, journal, and rollback APIs
  are self-contained.
- [ ] Failure types defined locally; no `JuliaShellError` dependency.
- [ ] Standalone test suite exercises all transaction phases without
  Profile/Pin/Dock types.
- [ ] Documented as a general-purpose transactional filesystem engine.

### `JSONLProtocol.jl` (library-shaped IPC boundary)

Purpose: keep framing, versioning, bounded decoding, structured errors, and
request validation independent from daemon business methods.

- [ ] Separate generic envelope/framing/validation from JuliaShell method
  names; expose a dispatcher-independent request and response contract.
- [ ] Define protocol version negotiation and compatibility rules for future
  minor/major versions, including an explicit handshake or capabilities reply.
- [~] Add bounded streaming decode, per-message and per-connection limits,
  malformed-input recovery, and socket-path validation fixtures. Bounded stream
  and message-count limits are implemented; recovery and socket fixtures remain.
- [ ] Preserve request IDs, idempotency metadata, structured remediation, and
  deterministic encoding as stable contract tests shared with QML fixtures.
- [ ] Keep daemon dispatch (`status`, `pins.*`, `apps.*`) in `Daemon.jl`, not in
  this module.

**Extraction readiness:**

- [x] JSON parser/encoder is self-contained with zero julia-shell imports.
- [x] Envelope framing, versioning, and bounded decoding work without
  domain-specific validation.
- [x] Request/response/event types defined locally; no `JuliaShellError`
  dependency in the codec layer.
- [x] Standalone codec tests exercise encode/decode, malformed input, stream
  message limits, and size limits; domain protocol tests cover version rejection.
- [x] Protocol validation for julia-shell methods stays in Protocol.jl, not
  in this module.

### `RuntimeProviders.jl` (library-shaped provider contract)

Purpose: coordinate optional desktop services through capability, health,
snapshot, event, subscription, and action boundaries.

- [~] Stabilize the current `AbstractShellProvider`, `ProviderHealth`,
  `ProviderEvent`, fake provider, and `SessionCoordinator` API. Callback
  subscriptions now exist for fake providers and the coordinator.
- [ ] Add provider lifecycle generations, bounded callback queues, action
  timeouts, subscription cleanup, and restart/unavailable transitions.
- [ ] Define snapshot immutability and redaction rules; secrets and private
  provider state must never enter the canonical projection or logs.
- [ ] Add contract tests every real provider must pass, plus deterministic
  fakes for unavailable, degraded, restarting, and slow states.
- [ ] Wire coordinator health and events into `Projection.jl` only after event
  ordering and stale-event behavior are specified.

**Extraction readiness:**

- [ ] `AbstractShellProvider`, `ProviderHealth`, `ProviderEvent`,
  `FakeShellProvider`, and `SessionCoordinator` have no julia-shell domain
  dependencies.
- [ ] Health model, event subscription, action invocation, and coordinator
  aggregation are self-contained.
- [ ] Failure types defined locally; no `JuliaShellError` dependency.
- [ ] Standalone test suite exercises registration, health, events,
  subscriptions, and coordinator lifecycle without JuliaShell module.
- [ ] Demonstrated as a general-purpose provider pattern (not just desktop
  services).

### `SystemdUser.jl` and `WaylandTransport.jl` (library-shaped platform seams)

Purpose: keep low-level operating-system bindings reusable while preventing
platform mechanisms from becoming desktop policy.

- [~] `SystemdUser.jl`: wrap native notify/watchdog and argv-safe user-unit
  control. Remaining work is lifecycle fixtures, environment import, target
  ordering, and independent scope launch integration.
- [~] `WaylandTransport.jl`: wrap display connection, fd, dispatch, flush,
  roundtrip, and capability discovery. Remaining work is registry discovery,
  generated XML protocol bindings, event queues, reconnect, and fake display
  tests.
- [ ] Keep protocol-family implementations separate (`SurfaceProvider`,
  `ToplevelProvider`, `WorkspaceProvider`, `OutputProvider`, `SeatProvider`,
  `SessionProvider`, `ClipboardProvider`, `CaptureProvider`, and
  `ActivationProvider`); do not grow one giant backend type.
- [ ] Add integration fixtures against the supported systemd and Wayland
  versions before changing the stable internal APIs.

**Extraction readiness (SystemdUser.jl):**

- [ ] Native `sd_notify` FFI and `SystemctlManager` have no julia-shell
  domain dependencies.
- [ ] Failure types defined locally; no `JuliaShellError` dependency.
- [ ] Standalone test suite exercises notify, watchdog, unit state, and
  enable/start/stop without JuliaShell module.
- [ ] Documented as a general-purpose systemd user-session binding.

**Extraction readiness (WaylandTransport.jl):**

- [ ] Display connection, fd, flush, roundtrip, and dispatch have no
  julia-shell domain dependencies.
- [ ] Failure types defined locally; no `JuliaShellError` dependency.
- [ ] Standalone test suite exercises connect, disconnect, error paths,
  and capability discovery without JuliaShell module.
- [ ] Documented as a general-purpose Wayland client transport.

### `ApplicationLauncher.jl` (library-shaped launch boundary)

Purpose: make launching a desktop entry a distinct capability instead of a
long-term responsibility of `AbstractCompositor`.

- [ ] Define a launcher interface returning a lifecycle-aware receipt, with
  safe argv, desktop-entry identity, activation token, scope, and failure
  reason.
- [ ] Add independent systemd-scope launching and activation-token support;
  preserve a fake launcher for projection and UI tests.
- [ ] Move compositor launch delegation behind this boundary without breaking
  current `apps.launch` protocol behavior.
- [ ] Add tests for absent entries, ambiguous identity, terminal apps, files/
  URLs, rejected shell metacharacters, and launch-service degradation.

**Extraction readiness:**

- [ ] Launcher interface and `LaunchReceipt` type have no julia-shell domain
  dependencies.
- [ ] Desktop-entry identity, activation token, scope, and lifecycle events
  are self-contained.
- [ ] Failure types defined locally; no `JuliaShellError` dependency.
- [ ] Standalone test suite exercises launch, focus, close, and degradation
  without JuliaShell module.
- [ ] Fake launcher demonstrated for projection and UI tests.

### `CompositorAbstractions.jl` (library-shaped compositor boundary)

Purpose: define compositor-neutral interfaces and state types so projection,
UI, and testing never depend on a specific compositor implementation.

- [x] Define `AbstractCompositor`, `OutputState`, `ToplevelState`,
  `WorkspaceState`, `WindowRef`, `CompositorEvent`, and `LaunchReceipt` as
  standalone types with no Domain.jl dependencies. `CompositorError` is local
  and the module no longer depends on Protocol.jl or `_string_dict`.
- [x] Add `FakeCompositor` as a first-class test fixture with deterministic
  outputs, toplevels, events, and launch receipts; remove its dependency on
  `decode_json` from Protocol.jl.
- [x] Define compositor event subscription and drain semantics as a stable API;
  callback subscriptions, unsubscribe tokens, and FIFO `drain_events!` are
  covered by standalone tests.
- [x] Add workspace derivation from toplevels as a default method; keep
  compositor-specific workspace queries behind adapters.
- [x] Test the module with deterministic fixtures only; no live Hyprland or
  Wayland session is required.

**Extraction readiness:**

- [x] `AbstractCompositor`, state types, event types, and `FakeCompositor` have
  no julia-shell domain dependencies (no Domain.jl, Protocol.jl, or
  Runtime.jl imports).
- [x] Event subscription and drain semantics are self-contained.
- [x] Failure types defined locally; no `JuliaShellError` dependency.
- [x] Standalone test suite exercises outputs, toplevels, workspaces, events,
  focus, close, and launch without JuliaShell module.
- [x] Documented as a general-purpose compositor abstraction layer with public
  API, extraction notes, default workspace derivation, and deterministic fake.

### Internal extraction rules

- [ ] Every module above must document ownership, public API, failure codes,
  state lifetime, and test seams before it is considered complete.
- [ ] Keep modules under `src/` and include them from `JuliaShell.jl`; do not
  add package dependencies solely to simulate an external-library boundary.
- [ ] Add compatibility wrappers while moving functions so CLI, daemon,
  projection, and QML contracts do not change accidentally.
- [ ] Revisit external extraction only after a module has stable tests,
  zero product-policy dependencies, and at least one demonstrated consumer
  outside its original call site.

## Abstraction focus order

This is the focused workstream for reducing coupling. It intentionally delays
new desktop-service features until the seams below are independently usable.

### A0 — enforce the abstraction contract

- [ ] For every library-shaped module, document four things in its source:
  ownership, public API, failure codes, and state lifetime.
- [ ] Add standalone tests that include the module directly, without loading
  `JuliaShell`, `Domain`, `Daemon`, QML, Wayland, or systemd unless the module
  is specifically the platform seam under test.
- [ ] Replace accidental parent-module references with local types/errors and
  explicit imports; compatibility wrappers belong only in `Apps.jl`,
  `JuliaShell.jl`, or the relevant product adapter.

### A1 — finish the smallest independent seams first

1. **`CompositorAbstractions.jl`** — settle event subscription/drain semantics,
   workspace derivation, local failures, and a direct standalone test suite.
2. **`JSONLProtocol.jl`** — separate generic framing/codec/version handling
   from JuliaShell method validation, then add standalone malformed-input,
   size-limit, and version tests.
3. **`RuntimeProviders.jl`** — define lifecycle generations, bounded event
   delivery, timeouts, subscription cleanup, and degraded/restart behavior;
   prove the contract with fake providers before wiring projection.
4. **`DesktopCatalog.jl`** — finish the catalog facade and cache invalidation;
   keep application identity and icon lookup out of projection internals.

These four modules are the low-risk abstraction spine: they have narrow state
models, deterministic fakes, and no requirement for a running desktop.

### A2 — extract safety and launch mechanics

5. **`TransactionalFS.jl`** — define generic file operations and ownership
   before moving more code from `Storage.jl`/`Reconcile.jl`; add exact-old-or-
   exact-new kill tests before exposing delete or cleanup operations.
6. **`ApplicationLauncher.jl`** — define lifecycle-aware launch receipts and
   safe argv first; then connect desktop-entry identity, activation tokens, and
   systemd scopes. Do not add more launch policy to `AbstractCompositor`.
7. **`BuildValidation.jl`/`Deploy.jl`** — finish exported-symbol checks, preflight,
   ownership manifests, dry-run deployment, and post-install health checks;
   these serve the other abstractions but must not become runtime authority.

### A3 — platform seams and integrations

8. **`SystemdUser.jl`** — make notify, watchdog, and user-unit control
   independently testable before enabling service activation.
9. **`WaylandTransport.jl`** — add registry/queue/reconnect contracts before
   protocol-family providers; keep Surface/Toplevel/Workspace/Output/Seat/etc.
   separate.
10. **Real providers** — only after A1/A2 contracts are stable, wire Hyprland,
    PipeWire, NetworkManager, BlueZ, UPower, MPRIS, portals, and accessibility
    services behind degraded-capable adapters.

### Abstraction definition of done

An abstraction is not complete when its type exists. Mark it complete only when
all of these hold:

- product policy can call it through a narrow interface;
- it has local failure types and no accidental product-domain imports;
- its state lifetime and event ordering are documented;
- a deterministic fake covers success, missing, degraded, restart, and timeout;
- its standalone tests pass without a live desktop; and
- at least one real caller uses the interface through a compatibility adapter.

Do not advance to the next layer merely because a module has been created. The
purpose of this sequence is to make each boundary replaceable before adding
more behavior behind it.

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
- `[x]` `Projection.jl`: build one deterministic state projection for pins,
  running applications, outputs, transactions, health, and degraded diagnostics.
  Serialize the same projection for daemon responses, CLI, and QML; long-lived
  event subscriptions remain.
- `[~]` `Compositor.jl`: define compositor-neutral interfaces and data types for
  `OutputState`, `ToplevelState`, `WorkspaceState`, `WindowRef`,
  `CompositorEvent`, and `LaunchReceipt`. Include a fake implementation
  contract so projection and UI tests do not require a live desktop. Workspace
  and reconnect event coverage remain.
- `[~]` `Hyprland.jl`: implement the first `Compositor.jl` adapter for outputs,
  windows, workspaces, focus, launch, open/close events, and identity evidence.
  Restart, reconnect backoff, event-socket, and output hotplug behavior remain.
- `[ ]` `DaemonWorker.jl`: move all daemon mutations behind one serialized
  worker, enforce per-connection idle timeouts, preserve request-id results,
  and provide graceful shutdown/PID lifecycle handling. The current advisory
  filesystem lock remains a cross-process safety layer, not a substitute for
  this worker.
- `[ ]` `Watchers.jl`: debounce profile and managed-target changes, recreate
  watchers after atomic replacement, run periodic hash reconciliation, and
  publish invalid-edit/degraded events while preserving the last valid revision.
  Depends on `Projection.jl` and `DaemonWorker.jl`.
- `[P]` `[ ]` `DaemonSocketTests` (test support): integration tests that start a
  real daemon, connect via Unix socket, and round-trip all 9 dispatched methods.
  Verify `state.changed` event emission after pin mutations. Currently only
  `_daemon_dispatch` for `state.get` is unit-tested.
- `[P]` `[x]` `JournalRecoveryTests` (test support): write mid-transaction
  journals, leave them incomplete, run `recover_journals!`, and assert
  exact-old or exact-new state. Currently `recover_journals!` has zero test
  coverage.
- `[P]` `[x]` `UnpinTests`: add test for `unpin!` with idempotent request IDs,
  revision tracking, missing-pin error, and duplicate-unpin rejection. Only
  `pin!` and `reorder!` are currently tested.

### Runtime And Platform Providers

- `[x]` `Systemd.jl`: add native `sd_notify` readiness, status, stopping, and
  watchdog support plus an argv-safe `SystemctlManager` user-unit adapter.
- `[~]` Package a `julia-shell.target` with separate notify-enabled daemon and
  Quickshell UI services. Add installation helpers, environment import,
  executable-path substitution, scope-based app launching, and live user-unit
  integration tests.
- `[~]` `Wayland.jl`: bind `libwayland-client` display connect/disconnect, fd,
  flush, roundtrip, and dispatch primitives. Add registry discovery, generated
  XML protocol bindings, queue ownership, reconnect, and fake-display tests.
- `[~]` `Runtime.jl`: define the common provider health, capability, snapshot,
  event, and action contract plus a deterministic `SessionCoordinator`. Wire
  real providers into the daemon worker and canonical projection.
- `[ ]` `SurfaceProvider`: layer-shell, fractional-scale, and viewporter.
- `[ ]` `ToplevelProvider`: ext/wlr foreign-toplevel listing and management.
- `[ ]` `WorkspaceProvider`: ext workspace protocol with compositor fallbacks.
- `[ ]` `OutputProvider`: wl/xdg output state, configuration, scale, and power.
- `[ ]` `SeatProvider`: pointer, keyboard, touch, input-method, and shortcut
  inhibition boundaries.
- `[ ]` `SessionProvider`: session lock, idle notification, and idle inhibitors.
- `[ ]` `ClipboardProvider`: data-control and primary-selection with bounded,
  private history.
- `[ ]` `CaptureProvider`: screencopy/image-copy-capture with portal fallback.
- `[ ]` `ActivationProvider`: xdg-activation tokens for launch and focus policy.
- `[ ]` `ApplicationLauncher`: desktop-entry launch into independent systemd
  scopes with activation tokens and lifecycle events; remove launch ownership
  from `AbstractCompositor`.
- `[ ]` Add `NotificationProvider`, `AudioProvider`, `NetworkProvider`,
  `BluetoothProvider`, `PowerProvider`, `MediaProvider`, `AppearanceProvider`,
  `SecretProvider`, `PortalProvider`, and `AccessibilityProvider`, each with an
  in-memory fake and explicit degraded behavior.
- `[ ]` Add a capability-scoped `PluginHost` with isolation, timeouts, bounded
  output/state, and no implicit filesystem, process, or network authority.

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
  interpolation. The `generated` mode is accepted by the domain schema but
  throws `JuliaShellError(:unsupported_mode, ...)` at staging time
  (`Reconcile.jl:180`); the renderer mechanism does not exist yet.
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

- [P] `[ ]` `DaemonSocketTests` (test support): integration tests that start a
  real daemon process, connect via Unix socket, round-trip all 9 dispatched
  methods, and verify `state.changed` event emission after pin mutations.
  Currently only `_daemon_dispatch` for `state.get` is unit-tested.
- [P] `[ ]` `JournalRecoveryTests` (test support): write mid-transaction
  journals, leave them incomplete, run `recover_journals!`, and assert
  exact-old or exact-new state. Currently `recover_journals!` has zero test
  coverage.
- `[ ]` `FaultInjection.jl` (test support): inject failures before and after
  journal writes, snapshot writes, stages, renames, verification, and process
  boundaries. Use it for exact-old-or-exact-new recovery assertions.
- `[ ]` `RecoveryDrill.jl` (test/release support): export a reference profile,
  restore it into a clean HOME/XDG tree, and compare canonical managed-file
  hashes, symlink metadata, and pin ordering.

### Dependency Sequence

1. Build `Projection.jl` and the fake `Compositor.jl` contract around the
   existing `DesktopEntries.jl` and pin model. **Complete.**
2. Add `DaemonWorker.jl` and `Watchers.jl`, then expand canonical projections
   and `state.changed` events through the protocol. Add `DaemonSocketTests`
   and `JournalRecoveryTests` to verify the daemon and recovery paths.
3. Finish the Hyprland adapter's event/reconnect path and harden the real
   output-aware QML shell.
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

- `[x]` `Compositor.jl`: define `AbstractCompositor`, `OutputState`, `ToplevelState`,
  `WindowRef`, `CompositorEvent`, and `LaunchReceipt` interfaces.
- `[~]` `Hyprland.jl`: implement the Hyprland adapter for outputs, toplevels, workspaces,
  focus, launch, open/close, and identity evidence. Reconnect and event socket
  handling remain.
- `[ ]` Add bounded reconnect backoff and degraded status on adapter disconnect.
- `[x]` `Compositor.jl`: add an in-memory fake adapter with deterministic
  fixtures for core and UI tests.
- `[ ]` Add Hyprland restart and output hotplug fixtures.

### Daemon And Protocol

- `[x]` Provide versioned newline-delimited JSON envelopes with a bounded
  message size and request/response helpers over a Unix socket.
- `[x]` Restrict the runtime directory and socket permissions to the user.
- `[~]` Serve status, plan, pin mutations, state projection, and app actions over
  the socket. Long-lived subscriptions and per-connection idle timeouts remain.
- `[~]` Pin mutations enforce revisions and bounded idempotency keys. `DaemonWorker.jl` must move all
  mutations behind a serialized queue and return the original response for a
  repeated request ID.
- `[ ]` Validate peer ownership where the host exposes Unix-socket credentials.
- `[x]` Publish health, active profile, revision, compositor, last transaction,
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
- [P] `[x]` Add `unpin!` test coverage: idempotent request IDs, revision
  tracking, missing-pin error, and duplicate-unpin rejection. Only `pin!` and
  `reorder!` are currently tested.
- `[x]` `Projection.jl`: merge pinned applications with normalized running-unpinned toplevels in
  one stable projection.
- `[~]` Implement absent-app launch, one-instance focus/workspace switching,
  and multiple-instance cycling. Direct launch and focus/close actions are
  present; workspace-aware routing and cycling remain.
- `[~]` Implement context actions for new instance, pin/unpin, close, details,
  and adjacent-output movement where supported. Pin/unpin and close are
  present; details and output movement remain.
- `[~]` Add per-output policies: preferred, focused, named, and all. Focused,
  preferred, and all are present; named selection remains.
- `[ ]` Add autohide policies: never, always, intelligent, with configurable
  reveal delay.
- `[ ]` Support keyboard focus, modifier+arrow reorder, delete confirmation or
  undo toast, and accessible announcements.

### Quickshell Presentation

- `[~]` Keep the `Projection.jl` QML state-projection fixture that renders malformed items as
  placeholders and exposes accessible names. It is now a real Quickshell shell;
  automated screenshot and malformed-item coverage remain.
- `[~]` Implement one compositor-aware `PanelWindow` per selected output. The
  current client creates one surface per connected Quickshell screen; named
  output filtering and duplicate-surface tests remain.
- `[ ]` Reserve exclusive zone only when configured and handle scale changes,
  output disconnect/reconnect, and duplicate-surface prevention.
- `[x]` Implement direct socket or bridge transport without allowing QML to edit
  profile TOML.
- `[ ]` Add optimistic pin/reorder updates that reconcile to a daemon revision
  or visibly revert within one second.
- [P] `[x]` Handle `state.changed` events in QML: replace the 4-second polling
  loop with event-driven projection updates. Currently `Main.qml:84-86`
  receives events but discards them (`return`). Use revision and topics from
  the event to trigger selective projection refresh.
- [P] `[x]` Bind `autohide` from projection: replace the hardcoded
  `"autohide": "never"` at `Main.qml:25` with a live binding to
  `projection.dock.autohide` so autohide policies take effect in the UI.
- `[~]` Add theme tokens for size, radius, spacing, opacity, color, animation,
  and reduced-motion behavior. The current client has shared color/size tokens
  and a reduced-motion setting; animation tokens remain.
- `[x]` Add visible non-color-only indicators for running, focused, urgent,
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
- [P] `[ ]` Daemon socket integration, journal recovery, and unpin test suites
  pass. These cover the three structural gaps identified in the pyramid.
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

# Pyramid of Intents

## Single core intent

**Make a person's Linux desktop continuity portable, inspectable, and safely
recoverable—so their configuration and everyday desktop workflow remain under
their control across machines and failures.**

`julia-shell` achieves this by making plain, version-controlled repository data
authoritative; treating every live change as a reviewed, recoverable
transaction; and exposing one canonical desktop state to the CLI, daemon, and
Quickshell UI.

This is a system intent, not merely a feature list. Higher layers only earn
their value because the layers below make them trustworthy.

## The pyramid

```text
                                      ┌──────────────────────────────────────────┐
                                      │ PORTABLE, TRUSTWORTHY DESKTOP CONTINUITY  │
                                      │   A user can carry, understand, safely    │
                                      │ recover, and use their desktop workflow.  │
                                      └─────────────────────┬────────────────────┘
                                                            │
                       ┌────────────────────────────────────┼────────────────────────────────────┐
                       │                                    │                                    │
              Product outcomes                      User-facing control                  Operational confidence
        A coherent desktop shell and             Predictable CLI/API/UI actions,        Changes survive interruption,
        dotfiles workflow work together.          portable profiles, meaningful state.   drift, retries, and recovery.
                       └────────────────────────────────────┼────────────────────────────────────┘
                                                            │
       ┌─────────────────────────────┬──────────────────────┼──────────────────────┬─────────────────────────────┐
       │                             │                      │                      │                             │
Desktop interaction             Desktop understanding    Configuration delivery       Service coordination
Launch, focus, close,           Discover applications,    Resolve, plan, snapshot,    One daemon, health,
group, and render windows.      identify windows, and     stage, commit, verify,       revisions, events, and
                                 retain missing pins.      restore desktop files.       degraded-mode behavior.
       └─────────────────────────────┴──────────────────────┼──────────────────────┴─────────────────────────────┘
                                                            │
     ┌─────────────────────┬───────────────────────┬────────┴────────┬──────────────────────┬─────────────────────┐
     │                     │                       │                 │                      │                     │
Authority & data         Safety & integrity       Stable contracts   Platform boundaries   Presentation boundary
Plain TOML/files are     Path containment,        Versioned JSONL,   Compositor, Wayland,  QML renders and
the source of truth;     hashes, locks,           canonical state,   systemd, and provider  interacts; it never
runtime metadata is      snapshots, journals,     revision checks,   abstractions isolate   becomes a competing
rebuildable.             rollback, idempotency.   request validation. OS-specific mechanisms. persistence authority.
     └─────────────────────┴───────────────────────┴────────┬────────┴──────────────────────┴─────────────────────┘
                                                            │
                                      ┌─────────────────────┴────────────────────┐
                                      │ FOUNDATIONS                              │
                                      │ Explicit ownership • deterministic data  │
                                      │ flow • least authority • observability   │
                                      │ • testable fakes • graceful degradation  │
                                      └──────────────────────────────────────────┘
```

## Intent layers, from foundation upward

### 1. Foundations: make behavior knowable and bounded

The system must be understandable before it can safely automate a desktop.
Its base intent is to avoid hidden authority and untestable machine-specific
behavior.

- **Explicit ownership.** The Julia package is the policy boundary. Repository
  TOML and `files/` are authoritative; journals, revisions, caches, sockets,
  and projections are operational or rebuildable state.
- **Determinism.** Profiles validate into domain types; plans are ordered and
  hashed; projections have stable schemas; request IDs make retries safe.
- **Least authority.** Only approved HOME/XDG variables expand. Sources stay
  within the repository and targets stay inside approved user roots. Launch
  arguments are argv values, never shell strings.
- **Observable failure.** Invalid, missing, conflicted, unavailable, and
  degraded states are explicit data, rather than conditions a client has to
  guess from.
- **Testable boundaries.** Fake compositor and shell-provider implementations
  let policy and UI behavior be exercised without a live Wayland session.

These are the non-negotiable load-bearing rules. A capability that bypasses
them is not an extension of julia-shell; it is a second system.

### 2. Authority, safety, contracts, and platform boundaries

This layer turns the foundation into a dependable service rather than a set of
scripts.

| Supporting intent | System rule | Current embodiment |
| --- | --- | --- |
| Preserve user ownership | Portable files describe desired state; runtime state does not contaminate the repository. | `profiles/<name>.toml`, `files/`, XDG-namespaced state |
| Make mutations recoverable | Never overwrite a live target until it is planned, snapshotted, staged, journaled, and later verified. | planner, snapshots, transaction journal, rollback, restore |
| Prevent conflicting writers | Serialize repository mutation and reject stale state instead of silently merging it. | advisory lock, revisions, idempotent request IDs |
| Keep clients interchangeable | The CLI and UI ask one authority for actions and state. | Julia core, versioned JSONL daemon protocol, canonical projection |
| Contain OS variation | Desktop mechanisms are adapters/providers, while policy remains stable. | compositor, Wayland, systemd, runtime-provider abstractions |
| Prevent a split brain | Presentation owns layout and ephemeral interaction only. | Quickshell reads projection and sends requests; it does not edit profile TOML |

The important dependency here is: **safe authority precedes convenient
interaction**. A beautiful dock that can silently corrupt or fork persistent
state would violate the core intent.

### 3. Capability intents: the pillars that make continuity useful

#### Configuration delivery

Intent: turn repository-declared configuration into live user configuration
without making deployment a leap of faith.

The pipeline is deliberately ordered:

```text
validate → resolve → plan → snapshot → stage → commit → verify
                         │                         │
                         └── review boundary ──────┴── recoverable boundary
```

It supports portable dotfile declarations, symlink-aware hashing, drift and
conflict classification, pre-change snapshots, rollback, journal recovery,
adoption, export, and restore. Planned additions—overlays, migrations,
generators, rich diffs, validated archives, retention, audit, bootstrap, and
fault injection—strengthen the same promise rather than changing it.

#### Desktop understanding

Intent: express durable user preference in terms of applications, not fragile
process IDs or transient window handles.

The application catalog scans XDG desktop entries, parses safe launch metadata,
and resolves identity using inspectable evidence. Durable pins survive absent
applications; running windows are normalized and grouped into a canonical state
projection. This permits a dock to say "this is your Firefox pin, currently
missing/running/focused" rather than pretending uncertainty does not exist.

#### Desktop interaction

Intent: make daily desktop actions available through a coherent, accessible
surface without moving policy into the UI.

The current slice supports launch, focus, close, pin, unpin, reorder, launcher
search, grouped dock items, multiple outputs, notifications, MPRIS controls,
tray, battery, and control-center presentation. Quickshell remains a client;
its polling and socket requests reconcile to the daemon projection. Remaining
work includes output hotplug, richer keyboard/a11y behavior, autohide, and
optimistic reconciliation.

#### Service coordination

Intent: let the desktop remain honest and useful when dependencies are absent,
restarting, or only partially available.

The daemon recovers journals before it serves clients and owns the Unix socket.
Systemd integration reports readiness and watchdog state. The runtime contract
defines provider capability, snapshot, event, action, and health shapes; the
projection exposes health and degraded diagnostics. Future worker queues,
watchers, long-lived subscriptions, peer validation, and reconnect behavior are
required to make this intent robust under sustained real-world use.

### 4. Product outcomes: what the structure enables

When the lower layers hold, users get four practical outcomes:

1. **Carry:** keep profiles and managed files as ordinary portable data, with
   machine-specific runtime metadata outside the repository.
2. **Understand:** inspect plans, application identity evidence, revisions,
   health, drift, and failures through CLI or protocol rather than opaque side
   effects.
3. **Act safely:** apply configuration and change pins deliberately, with
   confirmation, revision checks, locks, snapshots, and replay-safe requests.
4. **Recover and continue:** restore verified snapshots and surface degraded
   services instead of losing durable preferences or silently inventing state.

The UI is therefore a consequence of the product, not its definition: it is a
fast, pleasant way to work with the same durable desktop model available to all
clients.

## Current maturity: what can carry weight now

The repository is an executable **safe-core vertical slice**, not a completed
desktop environment. The following lower-to-middle layers are already present
and tested:

**Implemented and tested (8 test sets, 314 lines):**

- versioned profile/domain validation with 12 domain types and 2 error types;
  approved-variable expansion limited to HOME/XDG_ variables;
  user-root path containment via `safe_target_path`;
  SHA-256 hashing for files, directories, and symlinks without dereferencing;
- deterministic planning with 7 classifications (no\_op, create, drift,
  conflict, missing\_source, excluded, unsafe);
  snapshots before every live-target replacement;
  journaled apply/rollback/recovery with in-process rollback on failure;
  daemon startup journal recovery;
  per-repository advisory flock locks;
  atomic durable pin/unpin/reorder with revision tracking and idempotent
  request IDs;
- XDG desktop-entry scanning with locale-aware parsing;
  Exec field-code expansion into safe argv vectors;
  scored identity resolution (exact=100, alias=95, WMClass=90, normalized=80,
  exec\_basename=60);
  missing-pin preservation;
- canonical state projection (schema=1) merging pins, running windows, app
  metadata, outputs, workspaces, plan health, and degraded diagnostics;
  bounded versioned JSONL socket protocol (v1, 1 MiB limit);
  CLI with 16 commands and human/JSON output;
  daemon with journal recovery, method dispatch (9 methods), and state.changed
  event emission;
- FakeCompositor with deterministic fixtures;
  HyprlandCompositor adapter (outputs, toplevels, workspaces, focus, close,
  workspace switch, launch);
  FakeShellProvider with full action/subscription/event contract;
  SessionCoordinator with provider registration, polling, health aggregation,
  and event draining;
- native systemd sd\_notify via libsystemd.so FFI (readiness, status,
  watchdog, stopping);
  SystemctlManager for user-unit operations;
- libwayland-client display connection binding (connect, disconnect, fd,
  flush, roundtrip, dispatch);
- a real multi-monitor Quickshell presentation client (710 lines QML) with
  launcher, grouped dock, workspaces, notifications, MPRIS, tray, battery,
  control center, error toast, and reduced-motion support.

**Known structural gaps that must be closed before upper-layer features:**

- serialized daemon mutation worker (DaemonWorker.jl) to prevent concurrent
  CLI/daemon write races;
- debounced profile/target watchers with periodic hash reconciliation
  (Watchers.jl);
- state.changed event handling in QML (events are received but discarded;
  client falls back to 4-second polling);
- daemon socket integration tests (only `_daemon_dispatch` for `state.get` is
  unit-tested; no full socket lifecycle test);
- journal recovery and fault-injection tests;
- Hyprland reconnect, event-socket, and output hotplug behavior;
- full Wayland protocol bindings (foreign toplevels, workspaces, session lock,
  output management, etc.);
- overlays, migrations, generators, diffs, archive validation, retention,
  audit, bootstrap, and owned-target deletion policy;
- `generated` mode for DotfileEntry (explicitly throws "not enabled yet");
- performance benchmarks (pin/reorder latency, idle CPU/RSS, startup time);
- fault-injected transaction recovery and clean-home recovery drills.

The next structural gaps are not cosmetic: serialized daemon mutation work,
watchers/eventing, Hyprland reconnect and hotplug behavior, full real-provider
wiring, fault-injected transaction recovery, overlays/migrations/diffs, and
release/restore hardening. These should be built beneath or alongside new UI
features, never deferred in favor of a second policy path.

## Design tests for every future feature

A proposed feature belongs in this pyramid only if it can answer all of these:

1. **Authority:** Which existing authoritative data or policy boundary owns it?
2. **Safety:** What are its plan, confirmation, locking, snapshot, rollback,
   or idempotency semantics when it mutates state?
3. **Projection:** How does it appear in the one canonical versioned state, and
   how are unavailable or degraded conditions represented?
4. **Portability:** Which parts are portable repository intent versus local,
   rebuildable runtime facts?
5. **Boundary:** Is the OS/compositor/service-specific mechanism behind an
   adapter with a fake or contract fixture?
6. **Recovery:** After interruption, restart, retry, or external drift, can the
   system reach a known state without silent data loss?

If a feature cannot satisfy these questions, it should first be designed as a
lower-layer capability—not added directly to QML, a CLI shortcut, or a
compositor-specific code path.

## Evidence map

This intent model was derived from the executable code and its declared
contracts, principally:

- [`src/Domain.jl`](src/Domain.jl), [`src/Config.jl`](src/Config.jl),
  [`src/Storage.jl`](src/Storage.jl), and [`src/Reconcile.jl`](src/Reconcile.jl)
  for ownership, path policy, planning, transactions, and recovery;
- [`src/DesktopEntries.jl`](src/DesktopEntries.jl),
  [`src/Compositor.jl`](src/Compositor.jl), and
  [`src/Projection.jl`](src/Projection.jl) for desktop identity and canonical
  state;
- [`src/Protocol.jl`](src/Protocol.jl), [`src/Daemon.jl`](src/Daemon.jl),
  [`src/Runtime.jl`](src/Runtime.jl), [`src/Systemd.jl`](src/Systemd.jl), and
  [`src/Wayland.jl`](src/Wayland.jl) for service and platform boundaries;
- [`quickshell/Main.qml`](quickshell/Main.qml) for the presentation boundary;
  and
- [`README.md`](README.md), [`docs/architecture.md`](docs/architecture.md),
  [`docs/safety-and-recovery.md`](docs/safety-and-recovery.md),
  [`docs/runtime-abstractions.md`](docs/runtime-abstractions.md), and
  [`TODOS.md`](TODOS.md) for stated product scope and remaining dependencies.

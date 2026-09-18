# Runtime abstractions

A complete shell should separate operating-system mechanisms from desktop
policy. The Julia daemon owns policy and projects stable data; Quickshell owns
rendering and input surfaces. Protocol availability is negotiated at runtime.

## Implemented boundaries

| Boundary | Julia type | Responsibility |
| --- | --- | --- |
| Service lifecycle | `AbstractServiceManager`, `SystemctlManager` | Inspect and control user units with argv-safe `systemctl` calls |
| Daemon supervision | native `sd_notify` functions | Readiness, status, stopping, and watchdog heartbeats |
| Wayland transport | `AbstractWaylandBackend`, `WaylandDisplay` | Own a `wl_display`, expose its fd, flush, roundtrip, and dispatch |
| Compositor policy | `AbstractCompositor` | Outputs, workspaces, toplevels, focus, close, and workspace actions |
| Durable state | profile, storage, projection modules | Pins, configuration, revisions, transactions, and recovery |

The low-level Wayland binding deliberately does not duplicate Quickshell's
surface implementation. Its next layer should be generated from protocol XML
and registered against `WaylandDisplay`.

## Protocol-provider abstractions still needed

Do not create one giant `WaylandBackend`. Optional protocol families differ
between compositors and must degrade independently.

| Abstraction | Primary Wayland or desktop mechanisms | Shell features |
| --- | --- | --- |
| `SurfaceProvider` | layer-shell, fractional-scale, viewporter | bars, overlays, OSD, launcher placement |
| `ToplevelProvider` | ext/wlr foreign-toplevel protocols | task switcher, dock grouping, focus/close |
| `WorkspaceProvider` | ext workspace protocol or compositor adapter | workspace list, activate, move window |
| `OutputProvider` | `wl_output`, xdg-output, output-management | monitor topology, modes, scaling, power |
| `SeatProvider` | `wl_seat`, input-method, shortcuts-inhibit | pointer, keyboard, touch, global shortcuts |
| `SessionProvider` | session-lock, idle-notify, idle-inhibit | lock screen, idle policy, inhibitors |
| `ClipboardProvider` | data-control and primary-selection | clipboard history and paste actions |
| `CaptureProvider` | screencopy or image-copy-capture | screenshots, picker, previews |
| `ActivationProvider` | xdg-activation | launch tokens and focus-stealing prevention |

## Non-Wayland service abstractions still needed

- `ApplicationLauncher`: launch desktop entries into independent systemd
  scopes, carry activation tokens, and return lifecycle events. Application
  launch does not belong to the compositor interface long term.
- `NotificationProvider`: freedesktop notification server, persistence,
  grouping, actions, and do-not-disturb policy.
- `AudioProvider`: PipeWire graph and WirePlumber policy for volume, routing,
  default devices, and OSD events.
- `NetworkProvider`: NetworkManager state, Wi-Fi scans, activation, and secrets
  agent boundaries.
- `BluetoothProvider`: BlueZ discovery, pairing agent, trust, connect, and
  battery state.
- `PowerProvider`: UPower batteries, power profiles, logind actions, and
  inhibitor leases.
- `MediaProvider`: MPRIS players, arbitration, metadata, and transport actions.
- `AppearanceProvider`: wallpaper, color extraction, icon/theme lookup, and
  atomic theme revisions.
- `SecretProvider`: portal or Secret Service access without putting credentials
  in projections or logs.
- `PortalProvider`: screenshots, file chooser, settings, and remote-desktop
  requests through xdg-desktop-portal.
- `AccessibilityProvider`: AT-SPI announcements, focus semantics, reduced
  motion, contrast, and keyboard-only operation.
- `PluginHost`: capability-scoped extensions with timeouts and isolated state.
- `SessionCoordinator`: startup ordering, degraded-mode aggregation, restart
  policy, and one canonical state/event stream across all providers.

Each provider should expose `capabilities`, `snapshot`, `subscribe`, `invoke`,
and `health`, with an in-memory fake. The current fake provider and
`SessionCoordinator` implement callback subscriptions; real provider wiring,
timeouts, and restart generations remain. This common shape makes unavailable or
restarting services visible without bringing down the shell.

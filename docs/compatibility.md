# Compatibility and roadmap

This page records confidence boundaries, not promises. The safe core is the
verified part; desktop integration should not be treated as supported until the
integration spike and release checks are complete.

## Verified baseline

| Component | Current baseline | Status |
| --- | --- | --- |
| Operating system | Linux | Core tested on Linux |
| Julia | 1.9 or newer Julia 1.x | Core test suite exercised on Julia 1.12.7 |
| Operating environment | User-writable Linux HOME/XDG tree | Temporary-tree tests |
| Wayland compositor | Hyprland target | Adapter not implemented |
| Quickshell | Version to be pinned after the integration spike | QML fixture only |
| Qt | Version supplied by the chosen Quickshell package | Not yet validated |
| Packaging | Normal Julia project | PackageCompiler work pending |

The blueprint recommends pinning Quickshell v0.2.1 for the initial spike. That
version has not been validated in this checkout. Record the exact distribution,
Quickshell, Qt, Hyprland, Julia, and hardware versions before accepting UI or
performance results. A passing core test run does not certify shell, compositor,
or packaging compatibility.

## Delivery stages

1. **M0 discovery**: validate the real compositor/panel transport and record
   compatibility decisions.
2. **M1 safe core**: complete overlays, migrations, fault injection, and
   recovery tests. Repository locking and protocol shape validation are already
   present in the current slice.
3. **M2 app model**: implement compositor interfaces, Hyprland events,
   application launch/focus, and daemon projection events.
4. **M3 dock slice**: replace the QML fixture with real Quickshell output-aware
   surfaces and interaction behavior.
5. **M4 dotfiles workflow**: add bootstrap previews, full diffs, watchers,
   overlays, and audit history.
6. **M5 backup release**: add archive validation, retention, clean-home restore,
   packaging, checksums, and service installation docs.
7. **M6 hardening**: run the performance, accessibility, fault matrix, and
   second-person recovery gates.

The detailed requirement-by-requirement backlog is [`TODOS.md`](../TODOS.md).

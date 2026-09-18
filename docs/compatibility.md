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
| Wayland compositor | Hyprland target | Adapter implemented; live restart/reconnect coverage pending |
| Quickshell | 0.3.1 | Multi-monitor QML client smoke-parsed locally |
| Qt | Version supplied by the chosen Quickshell package | Not yet validated |
| Packaging | Normal Julia project | PackageCompiler work pending |

The current checkout was smoke-parsed with Quickshell 0.3.1. Record the exact
distribution, Qt, Hyprland, Julia, and hardware versions before accepting UI or
performance results. A passing core test run does not certify a live shell,
compositor, or packaging configuration; the adapter still needs restart,
reconnect, event-socket, and output-hotplug fixtures.

## Delivery stages

1. **M0 discovery**: validate the real compositor/panel transport and record
   compatibility decisions. The checked-in Quickshell 0.3.1 client is now the
   baseline.
2. **M1 safe core**: complete overlays, migrations, fault injection, and
   recovery tests. Repository locking and protocol shape validation are already
   present in the current slice.
3. **M2 app model**: compositor interfaces, application launch/focus, and the
   daemon projection are implemented; Hyprland event/reconnect hardening remains.
4. **M3 dock slice**: a real multi-monitor Quickshell surface is implemented;
   output policy tests, optimistic reconciliation, and hotplug hardening remain.
5. **M4 dotfiles workflow**: add bootstrap previews, full diffs, watchers,
   overlays, and audit history.
6. **M5 backup release**: add archive validation, retention, clean-home restore,
   packaging, checksums, and service installation docs.
7. **M6 hardening**: run the performance, accessibility, fault matrix, and
   second-person recovery gates.

The detailed requirement-by-requirement backlog is [`TODOS.md`](../TODOS.md).

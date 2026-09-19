module JuliaShell

using Dates
using Libdl
using SHA
using Sockets
using TOML
using UUIDs

include("BuildValidation.jl")
include("Deploy.jl")

include("Domain.jl")
include("Config.jl")
include("Storage.jl")
include("Reconcile.jl")
include("DesktopEntries.jl")
include("DesktopCatalog.jl")
include("Apps.jl")
include("JSONLProtocol.jl")
include("Protocol.jl")
include("Systemd.jl")
include("Wayland.jl")
include("Runtime.jl")
include("CompositorAbstractions.jl")
using .CompositorAbstractions
import .CompositorAbstractions: compositor_name, is_connected, compositor_outputs,
       compositor_toplevels, compositor_workspaces, refresh_compositor!,
       drain_events!, focus_toplevel!, close_toplevel!, switch_workspace!,
       launch_application!
include("Compositor.jl")
include("Projection.jl")
include("Daemon.jl")
include("CLI.jl")

export SUPPORTED_SCHEMA, Pin, Dock, DotfileEntry, Profile, PlanAction, Plan,
       BuildValidation, Deploy,
       SnapshotRef, TransactionResult, JuliaShellError, ValidationError,
       ValidationIssue, xdg_paths, repository_profile_path, init_repository,
       load_profile, save_profile, profile_dict, resolve_variables,
       profile_from_dict,
       safe_target_path, is_path_within, sha256_path, inspect_path,
       plan, apply!, create_snapshot, verify_snapshot, restore_snapshot,
       list_snapshots, adopt!, export_repository, recover_journals!,
       pin!, unpin!, reorder!, status, DesktopEntries, DesktopEntry, DesktopApp,
       DesktopEntryError, ApplicationIndex, parse_desktop_entry,
       discover_applications, scan_desktop_entries, parse_exec, exec_arguments,
       launch_arguments, normalize_app_id, resolve_application,
       resolve_icon,
       ApplicationCatalog, IdentityEvidence, IconResolution, CatalogError,
       build_catalog, resolve_window_identity, resolve_icon_safe,
       catalog_entry, search_catalog,
       AbstractServiceManager, SystemctlManager, SystemdUnitState,
       systemd_available, systemd_notify, notify_ready!, notify_status!,
       notify_watchdog!, notify_stopping!, watchdog_interval_seconds,
       unit_state, start_unit!, stop_unit!, restart_unit!, enable_unit!,
       disable_unit!, reload_systemd!,
       AbstractWaylandBackend, WaylandDisplay, wayland_available,
       connect_wayland, disconnect_wayland!, wayland_fd, wayland_error,
       flush_wayland!, roundtrip_wayland!, dispatch_wayland!,
       dispatch_wayland_pending!, wayland_capabilities,
       AbstractShellProvider, ProviderHealth, ProviderEvent, FakeShellProvider,
       SessionCoordinator, provider_name, provider_capabilities, provider_health,
       provider_snapshot, drain_provider_events!, push_provider_event!,
       register_action!, register_provider!, unregister_provider!, poll_providers!,
       drain_runtime_events!, subscribe_provider!, unsubscribe_provider!, subscribe_runtime!,
       unsubscribe_runtime!, invoke_provider!, runtime_snapshot,
       AbstractCompositor, CompositorError, WindowRef, OutputState, WorkspaceState, ToplevelState, CompositorEvent,
       LaunchReceipt, FakeCompositor, HyprlandCompositor, compositor_name,
       is_connected, compositor_outputs, compositor_toplevels, compositor_workspaces,
       refresh_compositor!,
        drain_events!, subscribe_compositor!, unsubscribe_compositor!, push_event!,
        focus_toplevel!, close_toplevel!, switch_workspace!,
       launch_application!, PROJECTION_SCHEMA, STATUSBAR_SCHEMA, state_projection, projection,
       PROTOCOL_VERSION, protocol_request, protocol_response,
       protocol_error, protocol_event, validate_protocol_request,
       encode_message, decode_message, request_daemon, run_daemon, main

end

module JuliaShell

using Dates
using SHA
using Sockets
using TOML
using UUIDs

include("Domain.jl")
include("Config.jl")
include("Storage.jl")
include("Reconcile.jl")
include("DesktopEntries.jl")
include("Apps.jl")
include("Protocol.jl")
include("Daemon.jl")
include("CLI.jl")

export SUPPORTED_SCHEMA, Pin, Dock, DotfileEntry, Profile, PlanAction, Plan,
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
       PROTOCOL_VERSION, protocol_request, protocol_response,
       protocol_error, protocol_event, validate_protocol_request,
       encode_message, decode_message, request_daemon, run_daemon, main

end

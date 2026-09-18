"Compatibility aliases for the original JuliaShell application API."
const DesktopApp = DesktopEntries.DesktopApp
const DesktopEntry = DesktopEntries.DesktopEntry
const DesktopEntryError = DesktopEntries.DesktopEntryError
const ApplicationIndex = DesktopEntries.ApplicationIndex

parse_desktop_entry(args...; kwargs...) = DesktopEntries.parse_desktop_entry(args...; kwargs...)
discover_applications(; kwargs...) = DesktopEntries.discover_applications(; kwargs...)
scan_desktop_entries(; kwargs...) = DesktopEntries.scan_desktop_entries(; kwargs...)
parse_exec(args...; kwargs...) = DesktopEntries.parse_exec(args...; kwargs...)
exec_arguments(args...; kwargs...) = DesktopEntries.exec_arguments(args...; kwargs...)
launch_arguments(args...; kwargs...) = DesktopEntries.launch_arguments(args...; kwargs...)
normalize_app_id(args...; kwargs...) = DesktopEntries.normalize_app_id(args...; kwargs...)
resolve_application(args...; kwargs...) = DesktopEntries.resolve_application(args...; kwargs...)
resolve_icon(args...; kwargs...) = DesktopEntries.resolve_icon(args...; kwargs...)

# Keep the old internal names available to existing JuliaShell tests and callers.
_exec_tokens(args...; kwargs...) = DesktopEntries.parse_exec(args...; kwargs...)
_exec_basename(args...; kwargs...) = DesktopEntries.exec_basename(args...; kwargs...)

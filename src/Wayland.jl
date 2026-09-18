"""Minimal libwayland-client binding and event-loop boundary.

This layer owns the display connection only. Generated bindings for optional
protocols (foreign toplevels, workspaces, session lock, idle notification,
output management, and data control) should be layered on top of it.
"""

abstract type AbstractWaylandBackend end

mutable struct WaylandDisplay <: AbstractWaylandBackend
    handle::Ptr{Cvoid}
    name::String
    fd::Int
    connected::Bool
    last_error::Union{Nothing,String}
end

const _libwayland = Ref{Ptr{Cvoid}}(C_NULL)
const _libwayland_checked = Ref(false)

function _libwayland_handle()
    _libwayland_checked[] && return _libwayland[]
    _libwayland_checked[] = true
    for candidate in ("libwayland-client.so.0", "libwayland-client.so")
        handle = Libdl.dlopen_e(candidate)
        handle == C_NULL || return (_libwayland[] = handle)
    end
    C_NULL
end

wayland_available() = _libwayland_handle() != C_NULL

function _wayland_symbol(name::Symbol)
    handle = _libwayland_handle()
    handle == C_NULL && throw(JuliaShellError(:wayland_unavailable,
        "libwayland-client is not installed";
        remediation="install the Wayland client library or use a compositor command adapter"))
    symbol = Libdl.dlsym_e(handle, name)
    symbol == C_NULL && throw(JuliaShellError(:wayland_unavailable,
        "libwayland-client is missing a required symbol";
        details=Dict("symbol" => String(name)), remediation="upgrade libwayland-client"))
    symbol
end

function _wayland_display_name(name, env)
    selected = name === nothing ? get(env, "WAYLAND_DISPLAY", "wayland-0") : String(name)
    isabspath(selected) && return selected
    runtime = get(env, "XDG_RUNTIME_DIR", "")
    isempty(runtime) ? selected : joinpath(runtime, selected)
end

"Connect to a Wayland display without taking ownership of any protocol objects."
function connect_wayland(; name=nothing, env=ENV, required=true)
    selected = _wayland_display_name(name, env)
    if !wayland_available()
        required && _wayland_symbol(:wl_display_connect)
        return nothing
    end
    handle = ccall(_wayland_symbol(:wl_display_connect), Ptr{Cvoid}, (Cstring,), selected)
    if handle == C_NULL
        required && throw(JuliaShellError(:wayland_connection_failed,
            "could not connect to the Wayland compositor";
            details=Dict("display" => selected),
            remediation="check WAYLAND_DISPLAY, XDG_RUNTIME_DIR, and compositor availability"))
        return nothing
    end
    fd = ccall(_wayland_symbol(:wl_display_get_fd), Cint, (Ptr{Cvoid},), handle)
    display = WaylandDisplay(handle, selected, Int(fd), true, nothing)
    finalizer(disconnect_wayland!, display)
    display
end

function _require_wayland(display::WaylandDisplay)
    display.connected && display.handle != C_NULL || throw(JuliaShellError(
        :wayland_disconnected, "Wayland display is disconnected";
        remediation="reconnect the Wayland backend before dispatching events"))
    display.handle
end

function disconnect_wayland!(display::WaylandDisplay)
    if display.connected && display.handle != C_NULL
        ccall(_wayland_symbol(:wl_display_disconnect), Cvoid, (Ptr{Cvoid},), display.handle)
    end
    display.handle = C_NULL
    display.fd = -1
    display.connected = false
    nothing
end

wayland_fd(display::WaylandDisplay) = (_require_wayland(display); display.fd)

function wayland_error(display::WaylandDisplay)
    display.handle == C_NULL && return 0
    Int(ccall(_wayland_symbol(:wl_display_get_error), Cint, (Ptr{Cvoid},), display.handle))
end

function _wayland_call!(display::WaylandDisplay, symbol::Symbol)
    result = Int(ccall(_wayland_symbol(symbol), Cint, (Ptr{Cvoid},), _require_wayland(display)))
    if result < 0
        errno = Libc.errno()
        symbol == :wl_display_flush && errno == Libc.EAGAIN && return result
        code = wayland_error(display)
        display.last_error = "$(symbol) failed with Wayland error $(code)"
        throw(JuliaShellError(:wayland_dispatch_failed, "Wayland connection operation failed";
            details=Dict("operation" => String(symbol), "error" => code, "errno" => errno),
            remediation="reconnect the compositor backend and rebuild protocol objects"))
    end
    result
end

flush_wayland!(display::WaylandDisplay) = _wayland_call!(display, :wl_display_flush)
roundtrip_wayland!(display::WaylandDisplay) = _wayland_call!(display, :wl_display_roundtrip)
dispatch_wayland!(display::WaylandDisplay) = _wayland_call!(display, :wl_display_dispatch)
dispatch_wayland_pending!(display::WaylandDisplay) =
    _wayland_call!(display, :wl_display_dispatch_pending)

"Protocol families a complete shell backend should negotiate through wl_registry."
function wayland_capabilities()
    Dict{String,Vector{String}}(
        "core" => ["wl_compositor", "wl_shm", "wl_seat", "wl_output"],
        "surface" => ["zwlr_layer_shell_v1", "wp_fractional_scale_manager_v1",
                      "wp_viewporter"],
        "desktop" => ["ext_foreign_toplevel_list_v1", "ext_workspace_manager_v1",
                      "xdg_activation_v1"],
        "session" => ["ext_session_lock_manager_v1", "ext_idle_notifier_v1",
                      "zwp_idle_inhibit_manager_v1"],
        "data" => ["zwlr_data_control_manager_v1", "zwp_primary_selection_device_manager_v1"],
        "output" => ["zwlr_output_manager_v1", "zwlr_output_power_manager_v1",
                      "wp_color_manager_v1"],
        "capture" => ["zwlr_screencopy_manager_v1", "ext_image_copy_capture_manager_v1"],
    )
end

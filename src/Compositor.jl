"""
Hyprland compositor adapter.

Implements the `AbstractCompositor` interface for Hyprland using `hyprctl`.
The pure types (`OutputState`, `ToplevelState`, etc.) and `FakeCompositor`
live in `CompositorAbstractions.jl`; this module only provides the
Hyprland-specific implementation.

This module depends on `Protocol.jl` (`decode_json`) for parsing hyprctl
JSON output, and `CompositorError` for structured error reporting.
"""

mutable struct HyprlandCompositor <: AbstractCompositor
    environment::Dict{String,String}
    output_states::Vector{OutputState}
    toplevel_states::Vector{ToplevelState}
    event_queue::Vector{CompositorEvent}
    connected::Bool
    last_error::Union{Nothing,String}
end

function HyprlandCompositor(; env=ENV, eager=true)
    compositor = HyprlandCompositor(Dict{String,String}(String(k) => String(v) for (k, v) in env),
                                    OutputState[], ToplevelState[], CompositorEvent[], false, nothing)
    eager && refresh_compositor!(compositor)
    compositor
end

_json_array(value) = value isa AbstractVector ? value : Any[]
_json_dict(value) = value isa AbstractDict ? _string_dict(value) : Dict{String,Any}()
_json_string(value, default="") = value === nothing ? String(default) : String(value)
_json_int(value, default=0) = value isa Integer ? Int(value) : try parse(Int, String(value)) catch; Int(default) end
_json_float(value, default=0.0) = value isa Number ? Float64(value) : try parse(Float64, String(value)) catch; Float64(default) end

function _hyprctl_json(compositor::HyprlandCompositor, command::AbstractString)
    binary = Sys.which("hyprctl")
    binary === nothing && throw(CompositorError(:compositor_unavailable, "hyprctl is not installed";
        remediation="install Hyprland's hyprctl or select another compositor"))
    output = try
        read(Cmd([String(binary), "-j", String(command)]), String)
    catch err
        throw(CompositorError(:compositor_unavailable, "hyprctl could not query Hyprland";
            details=Dict("command" => String(command), "error" => sprint(showerror, err)),
            remediation="check the Hyprland session and retry"))
    end
    try
        decode_json(output)
    catch err
        throw(CompositorError(:compositor_protocol, "Hyprland returned invalid JSON";
            details=Dict("command" => String(command), "error" => sprint(showerror, err)),
            remediation="upgrade or restart Hyprland and retry"))
    end
end

function refresh_compositor!(compositor::HyprlandCompositor)
    try
        monitor_values = _json_array(_hyprctl_json(compositor, "monitors"))
        client_values = _json_array(_hyprctl_json(compositor, "clients"))
        active = _json_dict(_hyprctl_json(compositor, "activewindow"))
        active_id = _json_string(get(active, "address", ""))
        outputs = OutputState[]
        output_names = Dict{Int,String}()
        for raw in monitor_values
            monitor = _json_dict(raw)
            id = _json_string(get(monitor, "name", get(monitor, "id", "")))
            isempty(id) && continue
            numeric_id = _json_int(get(monitor, "id", 0))
            output_names[numeric_id] = id
            push!(outputs, OutputState(id; name=id,
                width=_json_int(get(monitor, "width", 0)), height=_json_int(get(monitor, "height", 0)),
                scale=_json_float(get(monitor, "scale", 1.0)),
                focused=Bool(get(monitor, "focused", false)), available=true))
        end
        windows = ToplevelState[]
        for raw in client_values
            client = _json_dict(raw)
            mapped = Bool(get(client, "mapped", true))
            hidden = Bool(get(client, "hidden", false))
            mapped && !hidden || continue
            id = _json_string(get(client, "address", ""))
            isempty(id) && continue
            monitor_id = _json_int(get(client, "monitor", 0))
            workspace = _json_dict(get(client, "workspace", Dict{String,Any}()))
            workspace_id = _json_string(get(workspace, "name", get(workspace, "id", "")))
            class_name = _json_string(get(client, "class", ""))
            app_id = _json_string(get(client, "initialClass", class_name))
            push!(windows, ToplevelState(id, app_id;
                title=_json_string(get(client, "title", "")),
                output=get(output_names, monitor_id, ""), workspace=workspace_id,
                focused=id == active_id, urgent=Bool(get(client, "urgent", false)),
                pid=_json_int(get(client, "pid", 0)),
                class_name=isempty(class_name) ? nothing : class_name))
        end
        old_ids = Set(window.ref.id for window in compositor.toplevel_states)
        new_ids = Set(window.ref.id for window in windows)
        for id in setdiff(new_ids, old_ids)
            push_event!(compositor, CompositorEvent(:window_opened; payload=Dict("window_id" => id)))
        end
        for id in setdiff(old_ids, new_ids)
            push_event!(compositor, CompositorEvent(:window_closed; payload=Dict("window_id" => id)))
        end
        compositor.output_states = outputs
        compositor.toplevel_states = windows
        compositor.connected = true
        compositor.last_error = nothing
        true
    catch err
        compositor.connected = false
        compositor.last_error = sprint(showerror, err)
        false
    end
end

compositor_name(::HyprlandCompositor) = "hyprland"
is_connected(compositor::HyprlandCompositor) = compositor.connected
compositor_outputs(compositor::HyprlandCompositor) = copy(compositor.output_states)
compositor_toplevels(compositor::HyprlandCompositor) = copy(compositor.toplevel_states)

function drain_events!(compositor::HyprlandCompositor)
    events = copy(compositor.event_queue)
    empty!(compositor.event_queue)
    events
end

function _hyprctl_dispatch(compositor::HyprlandCompositor, arguments::Vector{String})
    binary = Sys.which("hyprctl")
    binary === nothing && _compositor_unavailable("control Hyprland")
    try
        run(Cmd(vcat([String(binary), "dispatch"], arguments)); wait=true)
    catch err
        throw(CompositorError(:compositor_command_failed, "Hyprland rejected the requested action";
            details=Dict("error" => sprint(showerror, err)), remediation="refresh the shell and retry"))
    end
    refresh_compositor!(compositor)
end

function focus_toplevel!(compositor::HyprlandCompositor, id::AbstractString)
    _hyprctl_dispatch(compositor, ["focuswindow", "address:" * String(id)])
end

function close_toplevel!(compositor::HyprlandCompositor, id::AbstractString)
    _hyprctl_dispatch(compositor, ["closewindow", "address:" * String(id)])
end

function switch_workspace!(compositor::HyprlandCompositor, workspace::AbstractString; output=nothing)
    output === nothing || _hyprctl_dispatch(compositor, ["focusmonitor", String(output)])
    _hyprctl_dispatch(compositor, ["workspace", String(workspace)])
end

function launch_application!(compositor::HyprlandCompositor, argv::AbstractVector{<:AbstractString})
    args = String[String(argument) for argument in argv]
    isempty(args) && throw(CompositorError(:invalid_launch, "launch argv cannot be empty";
        remediation="select an application with a valid desktop entry"))
    process = try
        run(Cmd(args); wait=false)
    catch err
        throw(CompositorError(:launch_failed, "application could not be started";
            details=Dict("error" => sprint(showerror, err)), remediation="check the desktop entry and retry"))
    end
    receipt = LaunchReceipt(string(uuid4()), args, true,
                            try Int(process.pid) catch; nothing end, "launch started")
    push_event!(compositor, CompositorEvent(:launch_requested;
        payload=Dict("id" => receipt.id, "argv" => args)))
    receipt
end

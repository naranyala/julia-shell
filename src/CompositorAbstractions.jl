#=
CompositorAbstractions — library-shaped compositor boundary.

Defines compositor-neutral interfaces and state types so projection, UI, and
testing never depend on a specific compositor implementation.  The fake adapter
is deliberately small so projection and QML contract tests can run without a
live Wayland session.

This module depends only on Julia stdlib (UUIDs).  It has no dependency on
`Domain`, `Config`, `Storage`, `Reconcile`, `Protocol`, `Runtime`, `Daemon`,
or `CLI`.

# Public API

- `AbstractCompositor`: abstract type for all compositor adapters.
- `WindowRef`, `OutputState`, `ToplevelState`, `WorkspaceState`: state types.
- `CompositorEvent`, `LaunchReceipt`: event and receipt types.
- `CompositorError`: local failure type (no `JuliaShellError` dependency).
- `FakeCompositor`: deterministic in-memory compositor for tests.
- Generic interface: `compositor_name`, `is_connected`, `compositor_outputs`,
  `compositor_toplevels`, `compositor_workspaces`, `refresh_compositor!`,
  `drain_events!`, `subscribe_compositor!`, `unsubscribe_compositor!`,
  `push_event!`, `focus_toplevel!`, `close_toplevel!`,
  `switch_workspace!`, `launch_application!`.

# Extraction readiness

- Zero imports from julia-shell domain modules.
- Failure type (`CompositorError`) defined locally.
- All public symbols documented with docstrings.
- Standalone test suite can exercise this module without JuliaShell.
=#

module CompositorAbstractions

using UUIDs: uuid4

export CompositorError, AbstractCompositor, WindowRef, OutputState, ToplevelState,
       WorkspaceState, CompositorEvent, LaunchReceipt, FakeCompositor,
       compositor_name, is_connected, compositor_outputs, compositor_toplevels,
       compositor_workspaces, refresh_compositor!, drain_events!,
       subscribe_compositor!, unsubscribe_compositor!, push_event!,
       focus_toplevel!, close_toplevel!, switch_workspace!, launch_application!

"""
    CompositorError(code::Symbol, message::String; details=nothing, remediation=nothing)

A compositor-level failure.  Structured to carry remediation hints without
depending on `JuliaShellError`.
"""
struct CompositorError <: Exception
    code::Symbol
    message::String
    details::Union{Nothing,Dict{String,Any}}
    remediation::Union{Nothing,String}
end

function CompositorError(code::Symbol, message::String;
                         details=nothing, remediation::Union{Nothing,String}=nothing)
    CompositorError(code, String(message),
                    details === nothing ? nothing : Dict{String,Any}(details),
                    remediation)
end

function Base.showerror(io::IO, e::CompositorError)
    print(io, "CompositorError(", e.code, "): ", e.message)
    e.remediation !== nothing && print(io, " — ", e.remediation)
end

abstract type AbstractCompositor end

"""
    WindowRef(id::String)

Opaque reference to a compositor-managed window.  The `id` is an opaque
string whose format is compositor-specific (e.g., Hyprland address).
"""
struct WindowRef
    id::String
end

WindowRef(id::AbstractString) = WindowRef(String(id))

"""
    OutputState(id, name, width, height, scale, focused, available)

Represents a connected display output.
"""
struct OutputState
    id::String
    name::String
    width::Int
    height::Int
    scale::Float64
    focused::Bool
    available::Bool
end

function OutputState(id::AbstractString; name=id, width=0, height=0, scale=1.0,
                     focused=false, available=true)
    OutputState(String(id), String(name), Int(width), Int(height), Float64(scale),
                Bool(focused), Bool(available))
end

"""
    ToplevelState(ref, app_id, title, output, workspace, focused, urgent, pid,
                  class_name, exec_basename)

Represents a top-level window managed by the compositor.
"""
struct ToplevelState
    ref::WindowRef
    app_id::String
    title::String
    output::String
    workspace::String
    focused::Bool
    urgent::Bool
    pid::Int
    class_name::Union{Nothing,String}
    exec_basename::Union{Nothing,String}
end

"""
    WorkspaceState(id, name, output, focused, urgent, window_count)

Represents a compositor workspace with aggregated window information.
"""
struct WorkspaceState
    id::String
    name::String
    output::String
    focused::Bool
    urgent::Bool
    window_count::Int
end

function WorkspaceState(id::AbstractString; name=id, output="", focused=false,
                        urgent=false, window_count=0)
    WorkspaceState(String(id), String(name), String(output), Bool(focused),
                   Bool(urgent), Int(window_count))
end

function ToplevelState(id::AbstractString, app_id::AbstractString; title="", output="",
                       workspace="", focused=false, urgent=false, pid=0,
                       class_name=nothing, exec_basename=nothing)
    ToplevelState(WindowRef(id), String(app_id), String(title), String(output),
                  String(workspace), Bool(focused), Bool(urgent), Int(pid),
                  class_name === nothing ? nothing : String(class_name),
                  exec_basename === nothing ? nothing : String(exec_basename))
end

"""
    CompositorEvent(kind::Symbol; payload=Dict{String,Any}())

An event emitted by the compositor.  `kind` is a symbol like `:window_opened`,
`:window_closed`, `:focus_changed`, `:workspace_changed`, or `:launch_requested`.
"""
struct CompositorEvent
    kind::Symbol
    payload::Dict{String,Any}
end

CompositorEvent(kind::Symbol; payload=Dict{String,Any}()) =
    CompositorEvent(kind, Dict{String,Any}(String(k) => deepcopy(v) for (k, v) in payload))

_copy_event(event::CompositorEvent) = CompositorEvent(event.kind; payload=event.payload)

"""
    LaunchReceipt(id, argv, accepted, pid, message)

Receipt returned after a launch request.  `accepted` indicates the compositor
accepted the request; `pid` is the process ID if known.
"""
struct LaunchReceipt
    id::String
    argv::Vector{String}
    accepted::Bool
    pid::Union{Nothing,Int}
    message::String
end

# --- Generic interface (default methods) ---

compositor_name(::AbstractCompositor) = "compositor"
is_connected(compositor::AbstractCompositor) = compositor.connected
compositor_outputs(compositor::AbstractCompositor) = OutputState[]
compositor_toplevels(compositor::AbstractCompositor) = ToplevelState[]
refresh_compositor!(::AbstractCompositor) = false

function drain_events!(compositor::AbstractCompositor)
    events = copy(compositor.event_queue)
    empty!(compositor.event_queue)
    events
end

subscribe_compositor!(::AbstractCompositor, ::Function) = nothing
unsubscribe_compositor!(::AbstractCompositor, token) = false
_notify_compositor_subscribers!(::AbstractCompositor, ::CompositorEvent) = nothing

function push_event!(compositor::AbstractCompositor, event::CompositorEvent)
    push!(compositor.event_queue, _copy_event(event))
    _notify_compositor_subscribers!(compositor, event)
    event
end

function compositor_workspaces(compositor::AbstractCompositor)
    grouped = Dict{Tuple{String,String},Vector{ToplevelState}}()
    for window in compositor_toplevels(compositor)
        isempty(window.workspace) && continue
        key = (window.workspace, window.output)
        push!(get!(grouped, key, ToplevelState[]), window)
    end
    result = WorkspaceState[]
    for ((name, output), windows) in sort(collect(grouped); by=item -> (item[1][2], item[1][1]))
        push!(result, WorkspaceState(name; name, output,
            focused=any(window -> window.focused, windows),
            urgent=any(window -> window.urgent, windows), window_count=length(windows)))
    end
    result
end

# --- Nothing compositor (graceful no-compositor mode) ---

compositor_outputs(::Nothing) = OutputState[]
compositor_toplevels(::Nothing) = ToplevelState[]
compositor_workspaces(::Nothing) = WorkspaceState[]
is_connected(::Nothing) = false
compositor_name(::Nothing) = "unknown"
refresh_compositor!(::Nothing) = false
drain_events!(::Nothing) = CompositorEvent[]

function _compositor_unavailable(operation::AbstractString)
    throw(CompositorError(:compositor_unavailable, "cannot $operation without a connected compositor";
        details=Dict("operation" => String(operation)),
        remediation="start a supported Wayland compositor and retry"))
end

focus_toplevel!(::Nothing, ::AbstractString) = _compositor_unavailable("focus a window")
close_toplevel!(::Nothing, ::AbstractString) = _compositor_unavailable("close a window")
switch_workspace!(::Nothing, ::AbstractString; output=nothing) = _compositor_unavailable("switch workspace")

# --- FakeCompositor ---

"""
A deterministic in-memory compositor used by tests and offline previews.
All operations are instant and testable without a live Wayland session.
"""
mutable struct FakeCompositor <: AbstractCompositor
    output_states::Vector{OutputState}
    toplevel_states::Vector{ToplevelState}
    event_queue::Vector{CompositorEvent}
    next_id::Int
    connected::Bool
    launches::Vector{Vector{String}}
    subscribers::Dict{UInt64,Function}
    next_subscription::UInt64
end

function FakeCompositor(; outputs=OutputState[], toplevels=ToplevelState[], connected=true)
    FakeCompositor(OutputState[output for output in outputs],
                   ToplevelState[toplevel for toplevel in toplevels],
                   CompositorEvent[], 1, Bool(connected), Vector{String}[],
                   Dict{UInt64,Function}(), UInt64(0))
end

compositor_name(::FakeCompositor) = "fake"
compositor_outputs(compositor::FakeCompositor) = copy(compositor.output_states)
compositor_toplevels(compositor::FakeCompositor) = copy(compositor.toplevel_states)
refresh_compositor!(compositor::FakeCompositor) = compositor.connected

function subscribe_compositor!(compositor::FakeCompositor, callback::Function)
    compositor.next_subscription += 1
    compositor.subscribers[compositor.next_subscription] = callback
    compositor.next_subscription
end

subscribe_compositor!(callback::Function, compositor::AbstractCompositor) =
    subscribe_compositor!(compositor, callback)

function unsubscribe_compositor!(compositor::FakeCompositor, token)
    token isa Integer && !(token isa Bool) && token >= 0 || return false
    converted = try
        UInt64(token)
    catch
        return false
    end
    pop!(compositor.subscribers, converted, nothing) !== nothing
end

function _notify_compositor_subscribers!(compositor::FakeCompositor, event::CompositorEvent)
    for callback in collect(values(compositor.subscribers))
        try
            callback(_copy_event(event))
        catch
            # A subscriber must not prevent the event from entering the queue.
        end
    end
    nothing
end

function _require_connected(compositor::FakeCompositor, operation::AbstractString)
    compositor.connected || _compositor_unavailable(operation)
end

function focus_toplevel!(compositor::FakeCompositor, id::AbstractString)
    _require_connected(compositor, "focus a window")
    index = findfirst(window -> window.ref.id == id, compositor.toplevel_states)
    index === nothing && throw(CompositorError(:window_missing, "window is no longer available";
        details=Dict("window_id" => String(id)), remediation="refresh the shell and retry"))
    compositor.toplevel_states = [
        ToplevelState(window.ref, window.app_id, window.title, window.output, window.workspace,
                      index == current_index, window.urgent, window.pid, window.class_name,
                      window.exec_basename)
        for (current_index, window) in enumerate(compositor.toplevel_states)
    ]
    push_event!(compositor, CompositorEvent(:focus_changed; payload=Dict("window_id" => String(id))))
    true
end

function close_toplevel!(compositor::FakeCompositor, id::AbstractString)
    _require_connected(compositor, "close a window")
    old_length = length(compositor.toplevel_states)
    filter!(window -> window.ref.id != id, compositor.toplevel_states)
    length(compositor.toplevel_states) == old_length &&
        throw(CompositorError(:window_missing, "window is no longer available";
            details=Dict("window_id" => String(id)), remediation="refresh the shell and retry"))
    push_event!(compositor, CompositorEvent(:window_closed; payload=Dict("window_id" => String(id))))
    true
end

function switch_workspace!(compositor::FakeCompositor, workspace::AbstractString; output=nothing)
    _require_connected(compositor, "switch workspace")
    selected_output = output === nothing ? nothing : String(output)
    payload = Dict{String,Any}("workspace" => String(workspace))
    selected_output === nothing || (payload["output"] = selected_output)
    push_event!(compositor, CompositorEvent(:workspace_changed;
        payload))
    true
end

function launch_application!(compositor::FakeCompositor, argv::AbstractVector{<:AbstractString})
    _require_connected(compositor, "launch an application")
    args = String[String(argument) for argument in argv]
    isempty(args) && throw(CompositorError(:invalid_launch, "launch argv cannot be empty";
        remediation="select an application with a valid desktop entry"))
    push!(compositor.launches, copy(args))
    receipt = LaunchReceipt(string(compositor.next_id), copy(args), true, nothing, "launch queued")
    compositor.next_id += 1
    push_event!(compositor, CompositorEvent(:launch_requested;
        payload=Dict("id" => receipt.id, "argv" => copy(args))))
    receipt
end

"Run an already validated desktop-entry argv when no compositor adapter is present."
function launch_application!(::Nothing, argv::AbstractVector{<:AbstractString})
    args = String[String(argument) for argument in argv]
    isempty(args) && throw(CompositorError(:invalid_launch, "launch argv cannot be empty";
        remediation="select an application with a valid desktop entry"))
    process = try
        run(Cmd(args); wait=false)
    catch err
        throw(CompositorError(:launch_failed, "application could not be started";
            details=Dict("error" => sprint(showerror, err)),
            remediation="check the desktop entry and retry"))
    end
    LaunchReceipt(string(uuid4()), args, true, try Int(process.pid) catch; nothing end,
                  "launch started")
end

end # module CompositorAbstractions

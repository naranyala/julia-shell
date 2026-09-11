const SUPPORTED_SCHEMA = 1

"A durable application pin. `desktop_id` is the portable identity key."
struct Pin
    desktop_id::String
    position::Int
    match_app_ids::Vector{String}
    launch::String
    label::Union{Nothing,String}
    scope::Union{Nothing,String}
end

function Pin(desktop_id::AbstractString; position::Integer=10,
             match_app_ids::AbstractVector{<:AbstractString}=String[],
             launch::AbstractString="desktop-entry", label=nothing, scope=nothing)
    isempty(strip(desktop_id)) && throw(ArgumentError("desktop_id cannot be empty"))
    position < 0 && throw(ArgumentError("position must be non-negative"))
    launch in ("desktop-entry", "command") ||
        throw(ArgumentError("launch must be desktop-entry or command"))
    Pin(String(desktop_id), Int(position), String[String(x) for x in match_app_ids],
        String(launch), label === nothing ? nothing : String(label),
        scope === nothing ? nothing : String(scope))
end

"Dock presentation policy and its ordered durable pins."
struct Dock
    edge::String
    output::String
    autohide::String
    pins::Vector{Pin}
end

function Dock(; edge="bottom", output="preferred", autohide="never", pins=Pin[])
    edge in ("top", "bottom", "left", "right") ||
        throw(ArgumentError("edge must be top, bottom, left, or right"))
    output in ("preferred", "focused", "all") ||
        throw(ArgumentError("output must be preferred, focused, or all"))
    autohide in ("never", "always", "intelligent") ||
        throw(ArgumentError("autohide must be never, always, or intelligent"))
    Dock(String(edge), String(output), String(autohide), Pin[p for p in pins])
end

"A managed file or directory declaration in a portable profile."
struct DotfileEntry
    id::String
    source::String
    target::String
    mode::String
    platforms::Vector{String}
    secret::Bool
    baseline_hash::Union{Nothing,String}
end

function DotfileEntry(id::AbstractString, source::AbstractString, target::AbstractString;
                      mode="symlink", platforms=["linux"], secret=false,
                      baseline_hash=nothing)
    isempty(strip(id)) && throw(ArgumentError("dotfile id cannot be empty"))
    isempty(strip(source)) && throw(ArgumentError("dotfile source cannot be empty"))
    isempty(strip(target)) && throw(ArgumentError("dotfile target cannot be empty"))
    mode in ("symlink", "copy", "generated") ||
        throw(ArgumentError("mode must be symlink, copy, or generated"))
    DotfileEntry(String(id), String(source), String(target), String(mode),
                 String[String(x) for x in platforms], Bool(secret),
                 baseline_hash === nothing ? nothing : String(baseline_hash))
end

"The validated portable profile loaded from one repository."
struct Profile
    schema::Int
    name::String
    dock::Dock
    dotfiles::Vector{DotfileEntry}
end

function Profile(name::AbstractString="personal"; schema=SUPPORTED_SCHEMA,
                 dock=Dock(), dotfiles=DotfileEntry[])
    isempty(strip(name)) && throw(ArgumentError("profile name cannot be empty"))
    Profile(Int(schema), String(name), dock, DotfileEntry[e for e in dotfiles])
end

"One deterministic change in a plan. `kind` is a stable classification symbol."
struct PlanAction
    id::String
    kind::Symbol
    source::Union{Nothing,String}
    target::String
    mode::Union{Nothing,String}
    source_hash::Union{Nothing,String}
    target_hash::Union{Nothing,String}
    reason::String
end

"A read-only description of changes, suitable for preview or hashing."
struct Plan
    id::String
    profile::String
    revision::Int
    actions::Vector{PlanAction}
    hash::String
    conflicts::Vector{String}
    unsafe::Vector{String}
    missing::Vector{String}
end

"Reference to an immutable completed or incomplete snapshot."
struct SnapshotRef
    id::String
    path::String
    status::String
    manifest_hash::String
end

"Result of a transaction, including the recovery information needed by callers."
struct TransactionResult
    id::String
    operation::String
    phase::Symbol
    revision::Int
    snapshot::Union{Nothing,SnapshotRef}
    message::String
    rolled_back::Bool
    journal::Union{Nothing,String}
end

struct ValidationIssue
    path::String
    field::String
    value::Any
    expected::String
    message::String
end

struct ValidationError <: Exception
    issues::Vector{ValidationIssue}
end

function Base.showerror(io::IO, err::ValidationError)
    print(io, "profile validation failed")
    for issue in err.issues
        print(io, "; ", issue.path, ".", issue.field, ": ", issue.message)
    end
end

struct JuliaShellError <: Exception
    code::Symbol
    message::String
    details::Dict{String,Any}
    remediation::String
end

JuliaShellError(code::Symbol, message::AbstractString;
              details=Dict{String,Any}(), remediation="") =
    JuliaShellError(code, String(message), Dict{String,Any}(string(k) => v for (k, v) in details),
                  String(remediation))

Base.showerror(io::IO, err::JuliaShellError) = print(io, err.message)

pin_sort_key(pin::Pin) = (pin.position, pin.desktop_id, something(pin.scope, ""))
ordered_pins(dock::Dock) = sort(copy(dock.pins); by=pin_sort_key)

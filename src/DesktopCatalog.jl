#=
DesktopCatalog — library-shaped application catalog boundary.

Provides a complete, reusable application catalog for the projection, launcher,
and compositor identity code.  Keeps XDG desktop-entry details out of the rest
of the product while exposing stable value types and a narrow public API.

This module depends only on `DesktopEntries` (a self-contained submodule) and
Julia stdlib.  It has no dependency on `Domain`, `Config`, `Storage`,
`Reconcile`, `Projection`, `Daemon`, or `CLI`.

# Public API

- `ApplicationCatalog`: immutable snapshot of discovered applications.
- `IdentityEvidence`: inspectable evidence for how a window was matched.
- `IconResolution`: resolved icon path or fallback.
- `build_catalog`: discover applications from XDG directories.
- `resolve_window_identity`: match a window to a catalog entry.
- `resolve_icon_safe`: resolve an icon name to a filesystem path.

# Extraction readiness

- Zero imports from julia-shell domain modules.
- Failure type (`CatalogError`) defined locally.
- All public symbols documented with docstrings.
- Standalone test suite can exercise this module without JuliaShell.
=#

"""
    CatalogError(message::String)

A failure in catalog construction or query.  Distinct from
`DesktopEntryError` (which is per-file) — this covers catalog-level issues.
"""
struct CatalogError <: Exception
    message::String
end

Base.showerror(io::IO, e::CatalogError) = print(io, "CatalogError: ", e.message)

"""
    ApplicationCatalog

Immutable snapshot of discovered applications.  Created by [`build_catalog`](@ref)
and consumed by projection, launcher, and compositor identity code.

# Fields

- `entries::ApplicationIndex`: mapping from desktop_id to `DesktopEntry`.
- `search_index::Vector{String}`: sorted desktop_ids for fast lookup.
- `total::Int`: total number of entries after filtering.
"""
struct ApplicationCatalog
    entries::DesktopEntries.ApplicationIndex
    search_index::Vector{String}
    total::Int
end

"""
    IdentityEvidence

Inspectable evidence for how a window was matched to a catalog entry.

# Fields

- `desktop_id::Union{Nothing,String}`: matched desktop entry ID.
- `method::Symbol`: resolution method (`:exact`, `:alias`, `:wm_class`,
  `:normalized`, `:exec_basename`, `:none`).
- `score::Int`: confidence score (0-100).
- `ambiguous::Bool`: whether multiple candidates matched.
"""
struct IdentityEvidence
    desktop_id::Union{Nothing,String}
    method::Symbol
    score::Int
    ambiguous::Bool
end

const NO_IDENTITY = IdentityEvidence(nothing, :none, 0, false)

"""
    IconResolution

Resolved icon path or a fallback indicator.

# Fields

- `path::Union{Nothing,String}`: filesystem path if resolved.
- `name::String`: original icon name or fallback string.
- `resolved::Bool`: whether a real icon was found.
"""
struct IconResolution
    path::Union{Nothing,String}
    name::String
    resolved::Bool
end

"""
    build_catalog(; dirs, env, locales, include_hidden) -> ApplicationCatalog

Discover XDG applications from the given directories and return an immutable
catalog snapshot.  Wraps `DesktopEntries.discover_applications` with a stable
return type.

# Arguments

- `dirs`: application directories to scan (default: XDG standard paths).
- `env`: environment variable dictionary (default: `ENV`).
- `locales`: locale preference list (default: system locales).
- `include_hidden`: whether to include `NoDisplay=true` entries (default: `false`).
"""
function build_catalog(; dirs=nothing, env=ENV, locales=nothing, include_hidden=false)
    entries = if dirs === nothing
        DesktopEntries.discover_applications(; env, locales, include_hidden)
    else
        DesktopEntries.discover_applications(; dirs, env, locales, include_hidden)
    end
    ids = sort!(collect(keys(entries)))
    ApplicationCatalog(entries, ids, length(ids))
end

"""
    resolve_window_identity(app_id; class_name, exec_basename, catalog, aliases, env)
        -> IdentityEvidence

Match a running window to a catalog entry using inspectable evidence.
Returns an `IdentityEvidence` with the matched desktop ID, method, score,
and ambiguity status.

# Arguments

- `app_id`: the window's reported application ID.
- `class_name`: optional `StartupWMClass` from the window.
- `exec_basename`: optional executable basename from the window.
- `catalog`: an `ApplicationCatalog` to search.
- `aliases`: optional user-defined alias mapping.
- `env`: environment variable dictionary.
"""
function resolve_window_identity(app_id::AbstractString;
                                 class_name=nothing, exec_basename=nothing,
                                 catalog::ApplicationCatalog=ApplicationCatalog(
                                     DesktopEntries.ApplicationIndex(), String[], 0),
                                 aliases::Union{Nothing,Dict{String,String}}=nothing,
                                 env=ENV)
    result = DesktopEntries.resolve_application(String(app_id);
        entries=catalog.entries, class_name, exec_basename, aliases, env)
    status = get(result, "status", "missing")
    status == "missing" && return NO_IDENTITY
    method_symbol = if status == "resolved"
        score = get(result, "score", 0)
        score >= 100 ? :exact :
        score >= 95  ? :alias :
        score >= 90  ? :wm_class :
        score >= 80  ? :normalized : :exec_basename
    else
        :none
    end
    IdentityEvidence(
        get(result, "desktop_id", nothing),
        method_symbol,
        get(result, "score", 0),
        get(result, "ambiguous", false)
    )
end

"""
    resolve_icon_safe(name; env) -> IconResolution

Resolve an icon name to a filesystem path, returning an `IconResolution` with
the path and resolution status.  Wraps `DesktopEntries.resolve_icon` with a
stable return type.
"""
function resolve_icon_safe(name::AbstractString; env=ENV)
    path = DesktopEntries.resolve_icon(String(name); env)
    IconResolution(path, String(name), path !== nothing)
end

"""
    catalog_entry(catalog, desktop_id) -> Union{Nothing,DesktopEntry}

Look up a single entry by desktop ID.  Returns `nothing` if not found.
"""
function catalog_entry(catalog::ApplicationCatalog, desktop_id::AbstractString)
    get(catalog.entries, String(desktop_id), nothing)
end

"""
    search_catalog(catalog, query; limit) -> Vector{DesktopEntry}

Search the catalog by name, generic name, or desktop ID.
Returns up to `limit` matches (default 36).
"""
function search_catalog(catalog::ApplicationCatalog, query::AbstractString; limit=36)
    q = lowercase(strip(String(query)))
    isempty(q) && return [catalog.entries[id] for id in Iterators.take(catalog.search_index, limit)]
    results = DesktopEntry[]
    for id in catalog.search_index
        entry = catalog.entries[id]
        occursin(q, lowercase(entry.name)) && (push!(results, entry); length(results) >= limit && break)
        entry.generic_name !== nothing && occursin(q, lowercase(entry.generic_name)) && (push!(results, entry); length(results) >= limit && break)
        occursin(q, lowercase(id)) && (push!(results, entry); length(results) >= limit && break)
    end
    results
end

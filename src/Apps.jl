struct DesktopApp
    desktop_id::String
    name::String
    icon::Union{Nothing,String}
    startup_wm_class::Union{Nothing,String}
    exec_basename::Union{Nothing,String}
    path::String
end

function _desktop_value(lines, key)
    for line in lines
        startswith(line, key * "=") && return strip(line[length(key)+2:end])
    end
    nothing
end

function _exec_basename(value)
    value === nothing && return nothing
    text = strip(String(value))
    isempty(text) && return nothing
    token = first(split(text))
    token = replace(token, r"%[fFuUdDnNickv]" => "")
    isempty(token) ? nothing : basename(token)
end

function _desktop_id(root::String, path::String)
    relative = relpath(path, root)
    endswith(relative, ".desktop") ? relative[1:end-8] * ".desktop" : relative
end

"Scan XDG desktop-entry directories into an inspectable application index."
function scan_desktop_entries(; dirs=nothing, env=ENV)
    roots = dirs === nothing ? begin
        data = xdg_paths(; env)
        String[joinpath(data["data"], "applications"),
                joinpath(get(env, "HOME", homedir()), ".local", "share", "applications"),
                "/usr/local/share/applications", "/usr/share/applications"]
    end : String[String(dir) for dir in dirs]
    apps = Dict{String,DesktopApp}()
    for root in unique(roots)
        isdir(root) || continue
        for (directory, _, files) in walkdir(root)
            for file in files
                endswith(file, ".desktop") || continue
                path = joinpath(directory, file)
                lines = try
                    readlines(path)
                catch
                    continue
                end
                any(==("[Desktop Entry]"), strip.(lines)) || continue
                hidden = lowercase(String(something(_desktop_value(lines, "NoDisplay"), "false"))) == "true" ||
                         lowercase(String(something(_desktop_value(lines, "Hidden"), "false"))) == "true"
                hidden && continue
                id = _desktop_id(root, path)
                name = String(something(_desktop_value(lines, "Name"), replace(file, ".desktop" => "")))
                icon = _desktop_value(lines, "Icon")
                startup = _desktop_value(lines, "StartupWMClass")
                apps[id] = DesktopApp(id, name, icon, startup, _exec_basename(_desktop_value(lines, "Exec")), path)
            end
        end
    end
    apps
end

_normalized_app_id(value::AbstractString) = lowercase(replace(replace(String(value), ".desktop" => ""), r"[^a-zA-Z0-9]" => ""))

"Resolve compositor identity using scored evidence without silently choosing ties."
function resolve_application(app_id::AbstractString=""; class_name="", exec_basename="",
                             entries=nothing, aliases=Dict{String,String}(), env=ENV)
    index = entries === nothing ? scan_desktop_entries(; env) : entries
    candidates = Dict{String,Any}[]
    requested = String(app_id)
    if haskey(aliases, requested) && haskey(index, String(aliases[requested]))
        push!(candidates, Dict{String,Any}("desktop_id" => String(aliases[requested]),
            "score" => 95, "evidence" => "user-defined alias"))
    end
    if haskey(index, requested)
        push!(candidates, Dict{String,Any}("desktop_id" => requested, "score" => 100,
                                           "evidence" => "exact desktop-file ID"))
    end
    normalized = _normalized_app_id(requested)
    for (id, app) in index
        _normalized_app_id(id) == normalized && push!(candidates,
            Dict{String,Any}("desktop_id" => id, "score" => 80,
                             "evidence" => "normalized app_id to filename"))
        class_name != "" && app.startup_wm_class !== nothing &&
            lowercase(app.startup_wm_class) == lowercase(String(class_name)) && push!(candidates,
            Dict{String,Any}("desktop_id" => id, "score" => 90, "evidence" => "StartupWMClass exact"))
        exec_basename != "" && app.exec_basename !== nothing &&
            lowercase(app.exec_basename) == lowercase(String(exec_basename)) && push!(candidates,
            Dict{String,Any}("desktop_id" => id, "score" => 60, "evidence" => "Exec basename"))
    end
    best = Dict{String,Any}()
    for candidate in candidates
        id = String(candidate["desktop_id"])
        if !haskey(best, id) || candidate["score"] > best[id]["score"]
            best[id] = candidate
        end
    end
    ranked = sort(collect(values(best)); by=x -> (-Int(x["score"]), String(x["desktop_id"])))
    if isempty(ranked)
        return Dict{String,Any}("status" => "missing", "desktop_id" => requested,
                                "candidates" => Any[], "missing" => true)
    end
    top_score = Int(ranked[1]["score"])
    tied = [item for item in ranked if Int(item["score"]) == top_score]
    if length(tied) > 1
        return Dict{String,Any}("status" => "ambiguous", "desktop_id" => nothing,
                                "candidates" => tied, "missing" => false)
    end
    selected = String(ranked[1]["desktop_id"])
    Dict{String,Any}("status" => "resolved", "desktop_id" => selected,
                     "score" => top_score, "evidence" => ranked[1]["evidence"],
                     "candidates" => ranked, "missing" => false)
end

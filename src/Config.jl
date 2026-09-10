const DEFAULT_ALLOWLIST = Set(["HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
                               "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR"])

function xdg_paths(; env=ENV)
    home = get(env, "HOME", homedir())
    config = get(env, "XDG_CONFIG_HOME", joinpath(home, ".config"))
    data = get(env, "XDG_DATA_HOME", joinpath(home, ".local", "share"))
    state = get(env, "XDG_STATE_HOME", joinpath(home, ".local", "state"))
    cache = get(env, "XDG_CACHE_HOME", joinpath(home, ".cache"))
    runtime = get(env, "XDG_RUNTIME_DIR", joinpath(tempdir(), "dockyard-runtime"))
    Dict{String,String}("home" => abspath(config == "" ? home : home),
                        "config" => abspath(config), "data" => abspath(data),
                        "state" => abspath(state), "cache" => abspath(cache),
                        "runtime" => abspath(runtime))
end

dockyard_state_dir(; env=ENV) = joinpath(xdg_paths(; env)["state"], "dockyard")
dockyard_cache_dir(; env=ENV) = joinpath(xdg_paths(; env)["cache"], "dockyard")
dockyard_runtime_dir(; env=ENV) = joinpath(xdg_paths(; env)["runtime"], "dockyard")

repository_profile_path(repo::AbstractString, profile::AbstractString="personal") =
    joinpath(abspath(repo), "profiles", String(profile) * ".toml")

function _string_dict(value)
    value isa AbstractDict || return Dict{String,Any}()
    Dict{String,Any}(String(k) => v for (k, v) in value)
end

function _issue(path, field, value, expected, message)
    ValidationIssue(String(path), String(field), value, String(expected), String(message))
end

function _required_string(table, key, path, issues; default=nothing)
    if !haskey(table, key)
        default === nothing && push!(issues, _issue(path, key, nothing, "string", "field is required"))
        return default
    end
    value = table[key]
    value isa AbstractString || push!(issues, _issue(path, key, value, "string", "expected a string"))
    value isa AbstractString ? String(value) : default
end

function _string_array(value, path, field, issues)
    value isa AbstractVector || begin
        push!(issues, _issue(path, field, value, "array of strings", "expected an array"))
        return String[]
    end
    result = String[]
    for (index, item) in enumerate(value)
        if item isa AbstractString
            push!(result, String(item))
        else
            push!(issues, _issue(path, "$field[$index]", item, "string", "expected a string"))
        end
    end
    result
end

function _parse_pin(raw, index, path, issues)
    table = _string_dict(raw)
    desktop_id = _required_string(table, "desktop_id", path, issues)
    position = get(table, "position", index * 10)
    position isa Integer || push!(issues, _issue(path, "position", position, "integer", "expected an integer"))
    match_ids = haskey(table, "match_app_ids") ? _string_array(table["match_app_ids"], path, "match_app_ids", issues) : String[]
    launch = get(table, "launch", "desktop-entry")
    launch isa AbstractString || push!(issues, _issue(path, "launch", launch, "desktop-entry or command", "expected a string"))
    launch = launch isa AbstractString ? String(launch) : "desktop-entry"
    launch in ("desktop-entry", "command") || push!(issues, _issue(path, "launch", launch, "desktop-entry or command", "unsupported launch mode"))
    label = get(table, "label", nothing)
    label !== nothing && !(label isa AbstractString) && push!(issues, _issue(path, "label", label, "string", "expected a string"))
    scope = get(table, "scope", nothing)
    scope !== nothing && !(scope isa AbstractString) && push!(issues, _issue(path, "scope", scope, "string", "expected a string"))
    if desktop_id isa String && position isa Integer
        try
            return Pin(desktop_id; position=position, match_app_ids=match_ids,
                       launch=launch, label=label, scope=scope)
        catch err
            push!(issues, _issue(path, "pin", raw, "valid pin", sprint(showerror, err)))
        end
    end
    nothing
end

function _parse_dotfile(raw, index, path, issues)
    table = _string_dict(raw)
    id = _required_string(table, "id", path, issues)
    source = _required_string(table, "source", path, issues)
    target = _required_string(table, "target", path, issues)
    mode = get(table, "mode", "symlink")
    mode isa AbstractString || push!(issues, _issue(path, "mode", mode, "symlink, copy, or generated", "expected a string"))
    mode = mode isa AbstractString ? String(mode) : "symlink"
    mode in ("symlink", "copy", "generated") || push!(issues, _issue(path, "mode", mode, "symlink, copy, or generated", "unsupported mode"))
    platforms = haskey(table, "platforms") ? _string_array(table["platforms"], path, "platforms", issues) : ["linux"]
    secret = get(table, "secret", false)
    secret isa Bool || push!(issues, _issue(path, "secret", secret, "boolean", "expected a boolean"))
    baseline = get(table, "baseline_hash", nothing)
    baseline !== nothing && !(baseline isa AbstractString) && push!(issues, _issue(path, "baseline_hash", baseline, "sha256 string", "expected a string"))
    if id isa String && source isa String && target isa String
        try
            return DotfileEntry(id, source, target; mode=mode, platforms=platforms,
                                secret=secret isa Bool ? secret : false, baseline_hash=baseline)
        catch err
            push!(issues, _issue(path, "entry", raw, "valid dotfile entry", sprint(showerror, err)))
        end
    end
    nothing
end

function profile_from_dict(raw; source_path="profile.toml")
    table = _string_dict(raw)
    issues = ValidationIssue[]
    schema = get(table, "schema", nothing)
    schema isa Integer || push!(issues, _issue(source_path, "schema", schema, "integer 1", "schema is required"))
    if schema isa Integer && schema != SUPPORTED_SCHEMA
        message = schema > SUPPORTED_SCHEMA ? "future schema is not supported" : "unsupported schema"
        push!(issues, _issue(source_path, "schema", schema, string(SUPPORTED_SCHEMA), message))
    end
    name = _required_string(table, "profile", source_path, issues)
    dock_table = haskey(table, "dock") ? _string_dict(table["dock"]) : Dict{String,Any}()
    haskey(table, "dock") || push!(issues, _issue(source_path, "dock", nothing, "table", "field is required"))
    edge = get(dock_table, "edge", "bottom")
    output = get(dock_table, "output", "preferred")
    autohide = get(dock_table, "autohide", "never")
    pins_raw = get(dock_table, "pins", Any[])
    pins_raw isa AbstractVector || begin
        push!(issues, _issue("$source_path.dock", "pins", pins_raw, "array of tables", "expected an array"))
        pins_raw = Any[]
    end
    pins = Pin[]
    for (index, raw_pin) in enumerate(pins_raw)
        pin = _parse_pin(raw_pin, index, "$source_path.dock.pins[$index]", issues)
        pin === nothing || push!(pins, pin)
    end
    dock = Dock()
    try
        dock = Dock(; edge=edge, output=output, autohide=autohide, pins=pins)
    catch err
        push!(issues, _issue("$source_path.dock", "policy", dock_table, "valid dock policy", sprint(showerror, err)))
        dock = Dock()
    end
    dotfiles_raw = get(table, "dotfiles", Any[])
    dotfiles_raw isa AbstractVector || begin
        push!(issues, _issue(source_path, "dotfiles", dotfiles_raw, "array of tables", "expected an array"))
        dotfiles_raw = Any[]
    end
    dotfiles = DotfileEntry[]
    ids = Set{String}()
    for (index, raw_entry) in enumerate(dotfiles_raw)
        entry = _parse_dotfile(raw_entry, index, "$source_path.dotfiles[$index]", issues)
        if entry !== nothing
            entry.id in ids && push!(issues, _issue(source_path, "dotfiles[$index].id", entry.id, "unique id", "duplicate entry id"))
            push!(ids, entry.id)
            push!(dotfiles, entry)
        end
    end
    desktop_ids = Set{Tuple{String,Union{Nothing,String}}}()
    for pin in pins
        key = (pin.desktop_id, pin.scope)
        key in desktop_ids && push!(issues, _issue(source_path, "dock.pins", pin.desktop_id, "unique desktop_id", "duplicate pin"))
        push!(desktop_ids, key)
    end
    !isempty(issues) && throw(ValidationError(issues))
    Profile(name; schema=schema, dock=dock, dotfiles=dotfiles)
end

load_profile(path::AbstractString) = profile_from_dict(TOML.parsefile(path); source_path=String(path))

function profile_dict(profile::Profile)
    dock = Dict{String,Any}("edge" => profile.dock.edge, "output" => profile.dock.output,
                            "autohide" => profile.dock.autohide)
    pins = Any[]
    for pin in ordered_pins(profile.dock)
        item = Dict{String,Any}("desktop_id" => pin.desktop_id, "position" => pin.position,
                                "match_app_ids" => copy(pin.match_app_ids), "launch" => pin.launch)
        pin.label === nothing || (item["label"] = pin.label)
        pin.scope === nothing || (item["scope"] = pin.scope)
        push!(pins, item)
    end
    dock["pins"] = pins
    dotfiles = Any[]
    for entry in profile.dotfiles
        item = Dict{String,Any}("id" => entry.id, "source" => entry.source,
                                "target" => entry.target, "mode" => entry.mode,
                                "platforms" => copy(entry.platforms), "secret" => entry.secret)
        entry.baseline_hash === nothing || (item["baseline_hash"] = entry.baseline_hash)
        push!(dotfiles, item)
    end
    Dict{String,Any}("schema" => profile.schema, "profile" => profile.name,
                     "dock" => dock, "dotfiles" => dotfiles)
end

function save_profile(path::AbstractString, profile::Profile)
    mkpath(dirname(abspath(path)))
    temp = String(path) * ".tmp-" * string(uuid4())
    open(temp, "w") do io
        TOML.print(io, profile_dict(profile))
        flush(io)
    end
    mv(temp, path; force=true)
    profile
end

function init_repository(repo::AbstractString; profile="personal", force=false)
    root = abspath(repo)
    if ispath(root) && !isdir(root)
        throw(DockyardError(:invalid_repository, "repository path is not a directory";
                            details=Dict("path" => root), remediation="choose a directory"))
    end
    isdir(root) || mkpath(root)
    profile_path = repository_profile_path(root, profile)
    isfile(profile_path) && !force &&
        throw(DockyardError(:already_initialized, "profile already exists";
                            details=Dict("path" => profile_path), remediation="use --force only to replace it"))
    mkpath(dirname(profile_path))
    mkpath(joinpath(root, "files"))
    save_profile(profile_path, Profile(profile))
    profile_path
end

function resolve_variables(value::AbstractString; env=ENV, allowlist=DEFAULT_ALLOWLIST)
    result = String(value)
    pattern = r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"
    while true
        match_result = match(pattern, result)
        match_result === nothing && return result
        name = match_result.captures[1]
        name in allowlist || throw(DockyardError(:disallowed_variable,
            "variable $name is not allowed in managed paths";
            details=Dict("variable" => name), remediation="use an approved XDG or HOME variable"))
        haskey(env, name) || throw(DockyardError(:missing_variable,
            "required variable $name is not set"; details=Dict("variable" => name),
            remediation="set the variable or use an absolute path"))
        result = replace(result, match_result.match => String(env[name]); count=1)
    end
end

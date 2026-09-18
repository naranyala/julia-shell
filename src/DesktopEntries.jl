module DesktopEntries

export DesktopEntry, DesktopApp, DesktopEntryError, ApplicationIndex,
       parse_desktop_entry, discover_applications, scan_desktop_entries,
       parse_exec, exec_arguments, launch_arguments, exec_basename,
       normalize_app_id, resolve_application, resolve_icon

"A parse or validation failure in one desktop-entry file."
struct DesktopEntryError <: Exception
    path::String
    message::String
end

Base.showerror(io::IO, error::DesktopEntryError) = print(io, error.path, ": ", error.message)

"A normalized, inspectable XDG application desktop entry."
struct DesktopEntry
    desktop_id::String
    name::String
    generic_name::Union{Nothing,String}
    icon::Union{Nothing,String}
    startup_wm_class::Union{Nothing,String}
    exec::Union{Nothing,String}
    exec_arguments::Vector{String}
    exec_basename::Union{Nothing,String}
    categories::Vector{String}
    mime_types::Vector{String}
    path::String
    terminal::Bool
    no_display::Bool
    hidden::Bool
    type::String
end

"Compatibility name used by the JuliaShell-facing API."
const DesktopApp = DesktopEntry
const ApplicationIndex = Dict{String,DesktopEntry}

function _desktop_error(path, message)
    DesktopEntryError(String(path), String(message))
end

function _parse_key_file(path::AbstractString)
    lines = try
        readlines(path)
    catch error
        throw(_desktop_error(path, "could not read desktop entry: " * sprint(showerror, error)))
    end
    in_desktop_group = false
    found_desktop_group = false
    values = Dict{String,String}()
    localized = Dict{String,Dict{String,String}}()
    for raw_line in lines
        line = strip(String(raw_line))
        isempty(line) && continue
        (startswith(line, '#') || startswith(line, ';')) && continue
        if startswith(line, '[') && endswith(line, ']')
            in_desktop_group = line == "[Desktop Entry]"
            found_desktop_group |= in_desktop_group
            continue
        end
        in_desktop_group || continue
        pieces = split(line, '='; limit=2)
        length(pieces) == 2 || continue
        key = strip(pieces[1])
        value = strip(pieces[2])
        isempty(key) && continue
        localized_match = match(r"^([^\[]+)\[([^]]+)\]$", key)
        if localized_match === nothing
            values[key] = value
        else
            base = String(localized_match.captures[1])
            locale = String(localized_match.captures[2])
            bucket = get!(localized, base, Dict{String,String}())
            bucket[locale] = value
        end
    end
    found_desktop_group || throw(_desktop_error(path, "missing [Desktop Entry] group"))
    values, localized
end

function _unescape_value(value::AbstractString)
    result = IOBuffer()
    characters = collect(String(value))
    index = 1
    while index <= length(characters)
        character = characters[index]
        if character != '\\'
            write(result, character)
            index += 1
            continue
        end
        index == length(characters) && throw(ArgumentError("trailing desktop-entry escape"))
        index += 1
        escaped = characters[index]
        replacements = Dict('s' => ' ', 'n' => '\n', 't' => '\t', 'r' => '\r',
                            '\\' => '\\', ';' => ';')
        haskey(replacements, escaped) ? write(result, replacements[escaped]) : begin
            write(result, '\\')
            write(result, escaped)
        end
        index += 1
    end
    String(take!(result))
end

function _locale_candidates(; env=ENV, locales=nothing)
    requested = locales === nothing ? String[] : String[String(locale) for locale in locales]
    if locales === nothing
        for key in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG")
            haskey(env, key) || continue
            append!(requested, split(String(env[key]), ':'))
        end
    end
    candidates = String[]
    for locale in requested
        normalized = split(split(String(locale), '.'; limit=2)[1], '@'; limit=2)[1]
        isempty(normalized) && continue
        normalized in candidates || push!(candidates, normalized)
        language = split(normalized, '_'; limit=2)[1]
        language in candidates || push!(candidates, language)
    end
    candidates
end

function _value(values, localized, key; env=ENV, locales=nothing, default=nothing)
    translations = get(localized, String(key), Dict{String,String}())
    for locale in _locale_candidates(; env, locales)
        haskey(translations, locale) && return _unescape_value(translations[locale])
    end
    haskey(values, String(key)) ? _unescape_value(values[String(key)]) : default
end

function _bool_value(value, default=false)
    value === nothing && return default
    lowered = lowercase(strip(String(value)))
    lowered == "true" ? true : lowered == "false" ? false : default
end

function _list_value(value)
    value === nothing && return String[]
    result = String[]
    buffer = IOBuffer()
    characters = collect(String(value))
    index = 1
    while index <= length(characters)
        character = characters[index]
        if character == ';'
            item = String(take!(buffer))
            isempty(item) || push!(result, _unescape_value(item))
            index += 1
        elseif character == '\\' && index < length(characters)
            write(buffer, character)
            index += 1
            write(buffer, characters[index])
            index += 1
        else
            write(buffer, character)
            index += 1
        end
    end
    item = String(take!(buffer))
    isempty(item) || push!(result, _unescape_value(item))
    result
end

"Parse an XDG desktop-entry Exec value into argv-like template tokens."
function parse_exec(value::AbstractString)
    tokens = String[]
    buffer = IOBuffer()
    quoted = false
    has_token = false
    characters = collect(String(value))
    index = 1
    while index <= length(characters)
        character = characters[index]
        if character == '\\'
            index == length(characters) && throw(ArgumentError("trailing desktop-entry Exec escape"))
            index += 1
            escaped = characters[index]
            if quoted && !(escaped in ('"', '\\', '`', '\$'))
                write(buffer, '\\')
            end
            write(buffer, escaped)
            has_token = true
        elseif character == '"'
            quoted = !quoted
            has_token = true
        elseif !quoted && isspace(character)
            if has_token
                push!(tokens, String(take!(buffer)))
                has_token = false
            end
        else
            write(buffer, character)
            has_token = true
        end
        index += 1
    end
    quoted && throw(ArgumentError("unterminated desktop-entry Exec quote"))
    has_token && push!(tokens, String(take!(buffer)))
    _validate_exec_fields(tokens)
end

const _FIELD_CODES = Set(['f', 'F', 'u', 'U', 'i', 'c', 'k', 'd', 'D', 'n', 'N', 'v', '%'])

function _field_matches(token)
    collect(eachmatch(r"%(.)", String(token)))
end

function _validate_exec_fields(tokens)
    for token in tokens
        characters = collect(String(token))
        index = 1
        while index <= length(characters)
            characters[index] == '%' || (index += 1; continue)
            index == length(characters) && throw(ArgumentError("trailing desktop-entry Exec field code"))
            code = characters[index + 1]
            code in _FIELD_CODES || throw(ArgumentError("unsupported desktop-entry Exec field code %$code"))
            index += 2
        end
    end
    tokens
end

function _first_or_empty(values)
    isempty(values) ? nothing : String(first(values))
end

function _expand_token(token; files=String[], urls=String[], name="", icon=nothing, desktop_file="")
    _validate_exec_fields([String(token)])
    matches = _field_matches(token)
    isempty(matches) && return String[String(token)]
    String(token) == "%f" && return isempty(files) ? String[] : String[String(first(files))]
    String(token) == "%F" && return String[String(file) for file in files]
    String(token) == "%u" && return isempty(urls) ? String[] : String[String(first(urls))]
    String(token) == "%U" && return String[String(url) for url in urls]
    String(token) == "%i" && return icon === nothing ? String[] : String["--icon", String(icon)]
    String(token) == "%d" && return isempty(files) ? String[] : String[dirname(String(first(files)))]
    String(token) == "%D" && return String[dirname(String(file)) for file in files]
    String(token) == "%n" && return isempty(files) ? String[] : String[basename(String(first(files)))]
    String(token) == "%N" && return String[basename(String(file)) for file in files]
    result = String(token)
    for match_result in matches
        code = match_result.captures[1][1]
        code in _FIELD_CODES || throw(ArgumentError("unsupported desktop-entry Exec field code %$code"))
        code in ('F', 'U', 'D', 'N', 'i') && throw(ArgumentError("Exec field code %$code must be a separate argument"))
        replacement = if code == '%'
            "%"
        elseif code == 'f'
            something(_first_or_empty(files), "")
        elseif code == 'u'
            something(_first_or_empty(urls), "")
        elseif code == 'c'
            String(name)
        elseif code == 'k'
            String(desktop_file)
        elseif code == 'd'
            isempty(files) ? "" : dirname(String(first(files)))
        elseif code == 'D'
            isempty(files) ? "" : join(dirname.(String[String(file) for file in files]), " ")
        elseif code == 'n'
            isempty(files) ? "" : basename(String(first(files)))
        elseif code == 'N'
            isempty(files) ? "" : join(basename.(String[String(file) for file in files]), " ")
        elseif code == 'v'
            ""
        else
            throw(ArgumentError("unsupported desktop-entry Exec field code %$code"))
        end
        result = replace(result, match_result.match => replacement; count=1)
    end
    String[result]
end

"Expand a desktop-entry Exec template without invoking a shell."
function exec_arguments(value::AbstractString; files=String[], urls=String[], name="",
                        icon=nothing, desktop_file="")
    tokens = parse_exec(value)
    result = String[]
    for token in tokens
        append!(result, _expand_token(token; files, urls, name, icon, desktop_file))
    end
    result
end

"Return the safe argv vector for an application entry."
function launch_arguments(entry::DesktopEntry; files=String[], urls=String[])
    entry.exec === nothing && return String[]
    exec_arguments(entry.exec; files, urls, name=entry.name, icon=entry.icon,
                   desktop_file=entry.path)
end

function exec_basename(value)
    value === nothing && return nothing
    tokens = parse_exec(String(value))
    isempty(tokens) && return nothing
    token = replace(tokens[1], r"%(?:f|F|u|U|i|c|k|d|D|n|N|v|%)" => "")
    isempty(token) || startswith(token, "%") ? nothing : basename(token)
end

function _desktop_id(root::String, path::String)
    relative = relpath(path, root)
    endswith(relative, ".desktop") ? relative[1:end-8] * ".desktop" : relative
end

"Parse one desktop-entry file, including its inspectable launch metadata."
function parse_desktop_entry(path::AbstractString; desktop_id=nothing, env=ENV, locales=nothing)
    values, localized = _parse_key_file(path)
    type = String(get(values, "Type", "Application"))
    name = String(something(_value(values, localized, "Name"; env, locales),
                            replace(basename(String(path)), ".desktop" => "")))
    exec = haskey(values, "Exec") ? String(values["Exec"]) : nothing
    exec_tokens = exec === nothing ? String[] : try
        parse_exec(exec)
    catch error
        throw(_desktop_error(path, "invalid Exec value: " * sprint(showerror, error)))
    end
    exec = exec === nothing ? nothing : String(exec)
    app_id = desktop_id === nothing ? replace(basename(String(path)), ".desktop" => ".desktop") : String(desktop_id)
    DesktopEntry(app_id, name,
                 _value(values, localized, "GenericName"; env, locales),
                 _value(values, localized, "Icon"; env, locales),
                 _value(values, localized, "StartupWMClass"; env, locales),
                 exec, exec_tokens, exec_basename(exec),
                 _list_value(get(values, "Categories", nothing)),
                 _list_value(get(values, "MimeType", nothing)),
                 abspath(String(path)), _bool_value(get(values, "Terminal", nothing)),
                 _bool_value(get(values, "NoDisplay", nothing)),
                 _bool_value(get(values, "Hidden", nothing)), type)
end

function _application_roots(; env=ENV)
    home = get(env, "HOME", homedir())
    data_home = get(env, "XDG_DATA_HOME", joinpath(home, ".local", "share"))
    data_dirs = get(env, "XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    roots = String[joinpath(String(data_home), "applications")]
    for directory in split(String(data_dirs), ':')
        isempty(directory) || push!(roots, joinpath(directory, "applications"))
    end
    unique(roots)
end

"Resolve an icon name to a safe existing theme/pixmap path when possible."
function resolve_icon(icon; env=ENV, theme="hicolor")
    icon === nothing && return nothing
    requested = strip(String(icon))
    isempty(requested) && return nothing
    if isabspath(requested)
        return isfile(requested) ? abspath(requested) : nothing
    end
    home = get(env, "HOME", homedir())
    data_home = get(env, "XDG_DATA_HOME", joinpath(home, ".local", "share"))
    data_dirs = get(env, "XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    roots = String[data_home]
    append!(roots, split(String(data_dirs), ':'))
    extensions = isempty(splitext(requested)[2]) ? ("", ".svg", ".png", ".xpm") : ("",)
    sizes = ("scalable", "512x512", "256x256", "128x128", "96x96", "64x64", "48x48", "32x32", "24x24", "16x16")
    for root in unique(roots)
        isempty(root) && continue
        for size in sizes
            for extension in extensions
                candidate = joinpath(root, "icons", String(theme), size, "apps", requested * extension)
                isfile(candidate) && return abspath(candidate)
            end
        end
        for extension in extensions
            candidate = joinpath(root, "pixmaps", requested * extension)
            isfile(candidate) && return abspath(candidate)
        end
    end
    nothing
end

"Discover visible XDG application entries, preserving user-directory precedence."
function discover_applications(; dirs=nothing, env=ENV, locales=nothing, include_hidden=false)
    roots = dirs === nothing ? _application_roots(; env) : String[String(dir) for dir in dirs]
    applications = ApplicationIndex()
    seen = Set{String}()
    for root in unique(roots)
        isdir(root) || continue
        for (directory, _, files) in walkdir(root)
            for file in files
                endswith(file, ".desktop") || continue
                path = joinpath(directory, file)
                id = _desktop_id(root, path)
                id in seen && continue
                entry = try
                    parse_desktop_entry(path; desktop_id=id, env, locales)
                catch
                    continue
                end
                entry.type == "Application" || continue
                push!(seen, id)
                (!include_hidden && (entry.no_display || entry.hidden)) && continue
                applications[id] = entry
            end
        end
    end
    applications
end

"Compatibility spelling retained for callers of the original JuliaShell API."
scan_desktop_entries(; kwargs...) = discover_applications(; kwargs...)

normalize_app_id(value::AbstractString) =
    lowercase(replace(replace(String(value), r"\.desktop$" => ""), r"[^a-zA-Z0-9]" => ""))

"Resolve compositor identity using scored evidence without silently choosing ties."
function resolve_application(app_id::AbstractString=""; class_name="", exec_basename="",
                             entries=nothing, aliases=Dict{String,String}(), env=ENV)
    index = entries === nothing ? discover_applications(; env) : entries
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
    normalized = normalize_app_id(requested)
    for (id, app) in index
        normalize_app_id(id) == normalized && push!(candidates,
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
    ranked = sort(collect(values(best)); by=item -> (-Int(item["score"]), String(item["desktop_id"])))
    isempty(ranked) && return Dict{String,Any}("status" => "missing", "desktop_id" => requested,
                                               "candidates" => Any[], "missing" => true)
    top_score = Int(ranked[1]["score"])
    tied = [item for item in ranked if Int(item["score"]) == top_score]
    length(tied) > 1 && return Dict{String,Any}("status" => "ambiguous", "desktop_id" => nothing,
                                                "candidates" => tied, "missing" => false)
    selected = String(ranked[1]["desktop_id"])
    Dict{String,Any}("status" => "resolved", "desktop_id" => selected,
                     "score" => top_score, "evidence" => ranked[1]["evidence"],
                     "candidates" => ranked, "missing" => false)
end

end

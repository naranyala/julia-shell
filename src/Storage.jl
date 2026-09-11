"Return true for regular paths and dangling symlinks alike."
_entry_exists(path::AbstractString) = ispath(path) || islink(path)

_resolved_link(path::AbstractString) = begin
    target = readlink(path)
    normpath(isabspath(target) ? target : joinpath(dirname(path), target))
end

function is_path_within(path::AbstractString, root::AbstractString)
    candidate = normpath(abspath(String(path)))
    boundary = normpath(abspath(String(root)))
    separator = boundary == string(Base.Filesystem.path_separator) ? boundary : boundary * string(Base.Filesystem.path_separator)
    candidate == boundary || startswith(candidate, separator)
end

function _nearest_existing_parent(path::AbstractString)
    current = abspath(path)
    while !_entry_exists(current)
        parent = dirname(current)
        parent == current && return current
        current = parent
    end
    current
end

function _approved_roots(; env=ENV, approved_roots=nothing)
    roots = approved_roots === nothing ? String[xdg_paths(; env)[key] for key in ("home", "config", "data", "state", "cache")] : String[abspath(String(root)) for root in approved_roots]
    unique(normpath.(roots))
end

"Resolve a target after variable expansion and reject paths outside user-owned roots."
function safe_target_path(target::AbstractString; env=ENV, approved_roots=nothing)
    expanded = resolve_variables(target; env=env)
    absolute = normpath(abspath(expanded))
    roots = _approved_roots(; env=env, approved_roots=approved_roots)
    parent = _nearest_existing_parent(dirname(absolute))
    resolved_parent = try
        realpath(parent)
    catch
        normpath(parent)
    end
    any(is_path_within(resolved_parent, root) for root in roots) ||
        throw(JuliaShellError(:unsafe_path, "target path is outside approved user roots";
                            details=Dict("target" => String(target), "resolved" => absolute,
                                         "approved_roots" => roots),
                            remediation="use a path below HOME or an XDG user directory"))
    absolute
end

function _safe_source_path(repo::AbstractString, source::AbstractString; env=ENV)
    expanded = resolve_variables(source; env=env)
    candidate = normpath(isabspath(expanded) ? expanded : joinpath(repo, expanded))
    is_path_within(candidate, repo) ||
        throw(JuliaShellError(:unsafe_path, "source path escapes the repository";
                            details=Dict("source" => String(source), "repository" => String(repo)),
                            remediation="use a relative path inside the repository files tree"))
    candidate
end

"Export portable profile metadata and files with a self-contained checksum manifest."
function export_repository(repo::AbstractString, destination::AbstractString; env=ENV)
    destination = abspath(String(destination))
    ispath(destination) && throw(JuliaShellError(:destination_exists, "export destination already exists";
        details=Dict("path" => destination), remediation="choose a new destination"))
    mkpath(destination)
    root = abspath(String(repo))
    for name in ("profiles", "files")
        source = joinpath(root, name)
        isdir(source) && _copy_entry(source, joinpath(destination, name))
    end
    files = Any[]
    for (directory, _, names) in walkdir(destination)
        for name in names
            full = joinpath(directory, name)
            relative = relpath(full, destination)
            relative == "manifest.toml" && continue
            push!(files, Dict{String,Any}("path" => relative, "sha256" => sha256_path(full)))
        end
    end
    sort!(files; by=item -> String(item["path"]))
    manifest = Dict{String,Any}("schema" => 1, "created_at" => string(now(UTC)),
                                "files" => files, "manifest_hash" => _manifest_hash(files))
    save_toml_atomic(joinpath(destination, "manifest.toml"), manifest)
    destination
end

function inspect_path(path::AbstractString)
    name = String(path)
    !_entry_exists(name) && return Dict{String,Any}("type" => "missing", "path" => name)
    kind = islink(name) ? "symlink" : isdir(name) ? "directory" : isfile(name) ? "file" : "other"
    info = Dict{String,Any}("type" => kind, "path" => name)
    st = lstat(name)
    info["size"] = Int(st.size)
    info["mode"] = Int(st.mode & 0o7777)
    islink(name) && (info["link_target"] = readlink(name))
    info
end

function _hash_bytes(bytes::Vector{UInt8})
    bytes2hex(sha256(bytes))
end

function _hash_entry(path::AbstractString)
    islink(path) && return _hash_bytes(Vector{UInt8}(codeunits("symlink\n" * readlink(path))))
    isfile(path) && return open(path, "r") do io
        _hash_bytes(read(io))
    end
    isdir(path) || return _hash_bytes(Vector{UInt8}(codeunits("other\n")))
    io = IOBuffer()
    for name in sort(readdir(path))
        child = joinpath(path, name)
        write(io, name, '\0', islink(child) ? "symlink" : isdir(child) ? "directory" : "file", '\0')
        write(io, _hash_entry(child), '\n')
    end
    _hash_bytes(take!(io))
end

"Compute a SHA-256 hash without dereferencing symlink targets."
sha256_path(path::AbstractString) = _entry_exists(path) ? _hash_entry(path) : nothing

function _copy_entry(source::AbstractString, destination::AbstractString)
    islink(source) && return (mkpath(dirname(destination)); symlink(readlink(source), destination))
    isfile(source) && begin
        mkpath(dirname(destination))
        cp(source, destination; force=true)
        chmod(destination, lstat(source).mode & 0o7777)
        return destination
    end
    isdir(source) || throw(ArgumentError("unsupported source entry: $source"))
    mkpath(destination)
    chmod(destination, lstat(source).mode & 0o7777)
    for name in readdir(source)
        _copy_entry(joinpath(source, name), joinpath(destination, name))
    end
    destination
end

function _remove_entry(path::AbstractString)
    _entry_exists(path) || return
    isdir(path) && !islink(path) ? rm(path; recursive=true, force=true) : rm(path; force=true)
end

function _stable_value(value)
    if value isa AbstractDict
        pairs = Tuple{String,Any}[(string(key), item) for (key, item) in value]
        sort!(pairs; by=first)
        return "{" * join([key * "=" * _stable_value(item) for (key, item) in pairs], ",") * "}"
    end
    value isa AbstractVector && return "[" * join(_stable_value.(value), ",") * "]"
    value isa Symbol && return string(value)
    value === nothing && return "null"
    replace(string(value), '\n' => "\\n")
end

_manifest_hash(manifest) = _hash_bytes(Vector{UInt8}(codeunits(_stable_value(manifest))))

function _snapshot_id()
    timestamp = Dates.format(now(UTC), "yyyymmddTHHMMSS.sssZ")
    timestamp * "-" * string(uuid4())
end

function _snapshot_root(root=nothing; env=ENV)
    root === nothing ? joinpath(juliashell_state_dir(; env), "snapshots") : abspath(String(root))
end

"Create an immutable snapshot of the existing targets named by plan actions."
function create_snapshot(actions::AbstractVector{<:PlanAction}; root=nothing, operation="apply",
                         profile="", plan_hash="", revision=0, reason=operation, env=ENV)
    snapshot_id = _snapshot_id()
    directory = joinpath(_snapshot_root(root; env), snapshot_id)
    content_dir = joinpath(directory, "content")
    mkpath(content_dir)
    manifest = Any[]
    metadata = Dict{String,Any}("schema" => 1, "id" => snapshot_id,
        "operation" => String(operation), "profile" => String(profile),
        "reason" => String(reason), "machine" => get(env, "HOSTNAME", "unknown"),
        "created_at" => string(now(UTC)), "status" => "incomplete",
        "plan_hash" => String(plan_hash), "revision" => Int(revision),
        "entries" => manifest)
    snapshot_file = joinpath(directory, "snapshot.toml")
    save_toml_atomic(snapshot_file, metadata)
    try
        index = 0
        for action in actions
            _entry_exists(action.target) || continue
            index += 1
            relative = joinpath("content", string(index) * "-" * action.id)
            payload = joinpath(directory, relative)
            _copy_entry(action.target, payload)
            info = inspect_path(action.target)
            entry = Dict{String,Any}("id" => action.id, "target" => action.target,
                "type" => info["type"], "mode" => info["mode"], "size" => info["size"],
                "sha256" => sha256_path(action.target), "relative" => relative)
            haskey(info, "link_target") && (entry["link_target"] = info["link_target"])
            push!(manifest, entry)
        end
        metadata["manifest_hash"] = _manifest_hash(manifest)
        metadata["status"] = "complete"
        save_toml_atomic(snapshot_file, metadata)
        SnapshotRef(snapshot_id, directory, "complete", metadata["manifest_hash"])
    catch err
        metadata["status"] = "incomplete"
        metadata["error"] = sprint(showerror, err)
        try
            save_toml_atomic(snapshot_file, metadata)
        catch
        end
        throw(JuliaShellError(:snapshot_failed, "snapshot could not be completed";
                            details=Dict("path" => directory, "error" => sprint(showerror, err)),
                            remediation="free snapshot storage and retry; the incomplete snapshot is not restorable"))
    end
end

function _load_snapshot(path::AbstractString)
    file = isfile(path) ? String(path) : joinpath(String(path), "snapshot.toml")
    isfile(file) || throw(JuliaShellError(:snapshot_missing, "snapshot manifest does not exist";
                                        details=Dict("path" => file), remediation="run snapshot list"))
    data = _string_dict(TOML.parsefile(file))
    get(data, "status", "incomplete") == "complete" ||
        throw(JuliaShellError(:snapshot_incomplete, "snapshot is incomplete and cannot be restored";
                            details=Dict("path" => dirname(file)), remediation="choose a completed snapshot"))
    data, dirname(file)
end

"Recompute manifest and payload hashes. Throws an integrity error on any mismatch."
function verify_snapshot(path::AbstractString)
    data, directory = _load_snapshot(path)
    entries = get(data, "entries", Any[])
    actual_manifest_hash = _manifest_hash(entries)
    expected_manifest_hash = String(get(data, "manifest_hash", ""))
    mismatches = String[]
    actual_manifest_hash == expected_manifest_hash || push!(mismatches, "manifest hash")
    for raw in entries
        entry = _string_dict(raw)
        relative = normpath(String(entry["relative"]))
        (isabspath(relative) || relative == ".." || startswith(relative, ".." * string(Base.Filesystem.path_separator))) &&
            (push!(mismatches, String(entry["id"]) * ": unsafe payload path"); continue)
        String(get(entry, "type", "")) == "symlink" && !haskey(entry, "link_target") &&
            (push!(mismatches, String(entry["id"]) * ": missing link metadata"); continue)
        payload = joinpath(directory, relative)
        _entry_exists(payload) || (push!(mismatches, String(entry["id"]) * ": missing payload"); continue)
        sha256_path(payload) == String(entry["sha256"]) || push!(mismatches, String(entry["id"]) * ": payload hash")
    end
    isempty(mismatches) || throw(JuliaShellError(:integrity_failure, "snapshot verification failed";
        details=Dict("path" => directory, "mismatches" => mismatches),
        remediation="do not restore this snapshot; recover it from another verified backup"))
    true
end

function list_snapshots(; root=nothing, env=ENV)
    directory = _snapshot_root(root; env)
    isdir(directory) || return Dict{String,Any}[]
    result = Dict{String,Any}[]
    for name in sort(readdir(directory); rev=true)
        file = joinpath(directory, name, "snapshot.toml")
        isfile(file) || continue
        data = _string_dict(TOML.parsefile(file))
        push!(result, Dict{String,Any}("id" => name, "path" => joinpath(directory, name),
                                       "status" => get(data, "status", "incomplete"),
                                       "created_at" => get(data, "created_at", ""),
                                       "operation" => get(data, "operation", "")))
    end
    result
end

function save_toml_atomic(path::AbstractString, data::AbstractDict)
    mkpath(dirname(abspath(path)))
    temp = String(path) * ".tmp-" * string(uuid4())
    open(temp, "w") do io
        TOML.print(io, data)
        flush(io)
    end
    mv(temp, path; force=true)
    path
end

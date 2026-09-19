"""
Build-time validation and metadata utilities for a JuliaShell checkout.

This module intentionally has no dependency on JuliaShell runtime policy. It is
safe to include from a standalone `build.jl` script and is also available as
`JuliaShell.BuildValidation` for tests and release tooling.
"""
module BuildValidation

using Dates
using SHA
using TOML

export BuildError, project_root, source_inventory, artifact_manifest,
       write_manifest, verify_manifest, validate_repository, source_syntax_check,
       exported_symbols, export_issues, fixture_check, release_metadata,
       build_report, main

struct BuildError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::BuildError) = print(io, error.message)

function project_root(path::AbstractString=@__DIR__)
    candidate = abspath(String(path))
    isfile(candidate) && (candidate = dirname(candidate))
    while true
        isfile(joinpath(candidate, "Project.toml")) && return candidate
        parent = dirname(candidate)
        parent == candidate && break
        candidate = parent
    end
    throw(BuildError(:project_missing, "could not locate Project.toml from $path"))
end

const _ROOT_FILES = ("Project.toml", "Manifest.toml", "README.md", "TODOS.md")
const _ROOT_DIRS = ("src", "test", "docs", "bin", "packaging", "quickshell")
const _IGNORED_DIRS = Set([".git", ".julia", "__pycache__", "node_modules"])

function _included(path::String, root::String)
    relative = replace(relpath(path, root), '\\' => '/')
    any(part -> part in _IGNORED_DIRS, splitpath(relative)) && return false
    startswith(relative, "build-manifest") && return false
    true
end

"Return sorted repository files that can contribute to a source artifact."
function source_inventory(root::AbstractString=project_root())
    root = abspath(String(root))
    isdir(root) || throw(BuildError(:repository_missing, "repository directory does not exist: $root"))
    files = String[]
    for file in _ROOT_FILES
        path = joinpath(root, file)
        isfile(path) && push!(files, replace(relpath(path, root), '\\' => '/'))
    end
    for directory in _ROOT_DIRS
        path = joinpath(root, directory)
        isdir(path) || continue
        for (current, _, names) in walkdir(path)
            for name in names
                full = joinpath(current, name)
                _included(full, root) && push!(files, replace(relpath(full, root), '\\' => '/'))
            end
        end
    end
    build = joinpath(root, "build.jl")
    isfile(build) && push!(files, "build.jl")
    sort!(unique!(files))
end

function _hash_file(path::String)
    open(path, "r") do io
        bytes2hex(SHA.sha256(io))
    end
end

function _manifest_hash(entries; schema=1, project="", version="")
    bytes2hex(SHA.sha256(codeunits(join(
        vcat([string("schema", '\0', schema), string("project", '\0', project),
              string("version", '\0', version)],
             [string(item["path"], '\0', item["size"], '\0', item["sha256"]) for item in entries]), "\n"))))
end

"Parse every Julia source file without loading runtime services or extensions."
function source_syntax_check(root::AbstractString=project_root())
    root = abspath(String(root))
    failures = String[]
    for relative in source_inventory(root)
        endswith(relative, ".jl") || continue
        path = joinpath(root, relative)
        try
            expression = Meta.parseall(read(path, String))
            incomplete = _incomplete_parse_error(expression)
            incomplete === nothing || throw(incomplete)
        catch error
            push!(failures, "$relative: " * sprint(showerror, error))
        end
    end
    failures
end

function _incomplete_parse_error(expression)
    expression isa Expr || return nothing
    expression.head in (:incomplete, :error) && return only(expression.args)
    for argument in expression.args
        error = _incomplete_parse_error(argument)
        error === nothing || return error
    end
    nothing
end

function _collect_exports!(expression, result::Set{String})
    expression isa Expr || return result
    if expression.head == :export
        for item in expression.args
            item isa Symbol && push!(result, String(item))
        end
    end
    for argument in expression.args
        _collect_exports!(argument, result)
    end
    result
end

"Return sorted names declared by the package entry module's `export` statements."
function exported_symbols(root::AbstractString=project_root())
    path = joinpath(abspath(String(root)), "src", "JuliaShell.jl")
    isfile(path) || return String[]
    expression = try
        Meta.parseall(read(path, String))
    catch
        return String[]
    end
    sort!(collect(_collect_exports!(expression, Set{String}())))
end

"Return exported names that do not occur in any Julia source file."
function export_issues(root::AbstractString=project_root())
    root = abspath(String(root))
    files = filter(relative -> endswith(relative, ".jl"), source_inventory(root))
    definitions = Set{String}()
    for relative in files
        expression = try
            Meta.parseall(read(joinpath(root, relative), String))
        catch
            continue
        end
        _collect_definitions!(expression, definitions)
    end
    ["exported symbol is not defined in source tree: $name"
     for name in exported_symbols(root) if !(name in definitions)]
end

function _defined_name(expression)
    expression isa Symbol && return String(expression)
    expression isa Expr || return nothing
    expression.head in (:call, :where, :(::), :curly) && return _defined_name(first(expression.args))
    nothing
end

function _collect_definitions!(expression, result::Set{String})
    expression isa Expr || return result
    if expression.head == :module
        name = findfirst(argument -> argument isa Symbol, expression.args)
        name === nothing || push!(result, String(expression.args[name]))
    elseif expression.head in (:struct, :abstract, :primitive)
        for argument in expression.args
            name = _defined_name(argument)
            name === nothing || (push!(result, name); break)
        end
    elseif expression.head == :function
        name = _defined_name(first(expression.args))
        name === nothing || push!(result, name)
    elseif expression.head == :(=)
        name = _defined_name(first(expression.args))
        name === nothing || push!(result, name)
    elseif expression.head == :const
        for argument in expression.args
            name = argument isa Expr && argument.head == :(=) ? _defined_name(first(argument.args)) : _defined_name(argument)
            name === nothing || push!(result, name)
        end
    end
    expression.head == :export && return result
    for argument in expression.args
        _collect_definitions!(argument, result)
    end
    result
end

"Validate TOML fixtures and profile documents without invoking the daemon."
function fixture_check(root::AbstractString=project_root())
    root = abspath(String(root))
    failures = String[]
    for directory in ("profiles", "fixtures")
        path = joinpath(root, directory)
        isdir(path) || continue
        for (current, _, names) in walkdir(path)
            for name in names
                endswith(name, ".toml") || continue
                file = joinpath(current, name)
                try
                    TOML.parsefile(file)
                catch error
                    push!(failures, "$file: " * sprint(showerror, error))
                end
            end
        end
    end
    failures
end

function _git_revision(root::String)
    try
        strip(read(pipeline(`git -C $root rev-parse HEAD`; stderr=devnull), String))
    catch
        nothing
    end
end

"Return release metadata without modifying the checkout or contacting a network."
function release_metadata(root::AbstractString=project_root())
    root = abspath(String(root))
    project = TOML.parsefile(joinpath(root, "Project.toml"))
    Dict{String,Any}(
        "project" => String(get(project, "name", "JuliaShell")),
        "version" => String(get(project, "version", "0.0.0")),
        "julia_version" => string(VERSION),
        "kernel" => string(Sys.KERNEL),
        "machine" => string(Sys.MACHINE),
        "git_revision" => _git_revision(root),
    )
end

"Create a deterministic manifest of source paths, sizes, and SHA-256 hashes."
function artifact_manifest(root::AbstractString=project_root(); files=nothing)
    root = abspath(String(root))
    paths = files === nothing ? source_inventory(root) : sort!(unique!(String[String(x) for x in files]))
    entries = Any[]
    for relative in paths
        relative, full = _safe_manifest_path(root, relative)
        isfile(full) || throw(BuildError(:manifest_input_missing, "manifest input does not exist: $relative"))
        push!(entries, Dict{String,Any}("path" => relative, "size" => filesize(full),
                                        "sha256" => _hash_file(full)))
    end
    project = TOML.parsefile(joinpath(root, "Project.toml"))
    project_name = String(get(project, "name", "JuliaShell"))
    version = String(get(project, "version", "0.0.0"))
    Dict{String,Any}("schema" => 1, "project" => project_name,
                     "version" => version, "files" => entries,
                     "manifest_hash" => _manifest_hash(entries; project=project_name, version))
end

function _safe_manifest_path(root::String, relative::AbstractString)
    relative = String(relative)
    isempty(relative) && throw(BuildError(:manifest_unsafe, "manifest path cannot be empty"))
    isabspath(relative) && throw(BuildError(:manifest_unsafe, "manifest contains an absolute path: $relative"))
    normalized = normpath(relative)
    normalized == relative || throw(BuildError(:manifest_unsafe, "manifest path is not canonical: $relative"))
    startswith(normalized, ".." * string(Base.Filesystem.path_separator)) &&
        throw(BuildError(:manifest_unsafe, "manifest path escapes repository: $relative"))
    full = joinpath(root, normalized)
    if ispath(full)
        canonical_root = realpath(root)
        canonical = realpath(full)
        outside = relpath(canonical, canonical_root)
        (outside == ".." || startswith(outside, ".." * string(Base.Filesystem.path_separator))) &&
            throw(BuildError(:manifest_unsafe, "manifest path resolves outside repository: $relative"))
    end
    normalized, full
end

function write_manifest(path::AbstractString, manifest::AbstractDict)
    destination = abspath(String(path))
    mkpath(dirname(destination))
    temporary = destination * ".tmp-" * string(getpid())
    open(temporary, "w") do io
        TOML.print(io, Dict{String,Any}(String(k) => v for (k, v) in manifest))
        flush(io)
    end
    mv(temporary, destination; force=true)
    destination
end

"Verify every recorded file and the deterministic manifest hash."
function verify_manifest(path::AbstractString; root=dirname(abspath(String(path))))
    manifest = try
        TOML.parsefile(path)
    catch error
        throw(BuildError(:manifest_invalid, "could not parse build manifest: " * sprint(showerror, error)))
    end
    files = get(manifest, "files", Any[])
    files isa AbstractVector || throw(BuildError(:manifest_invalid, "manifest files must be an array"))
    schema = get(manifest, "schema", nothing)
    schema isa Integer && !(schema isa Bool) && schema == 1 ||
        throw(BuildError(:manifest_invalid, "manifest schema must be 1"))
    project = get(manifest, "project", nothing)
    project isa AbstractString && !isempty(project) ||
        throw(BuildError(:manifest_invalid, "manifest project must be a non-empty string"))
    version = get(manifest, "version", nothing)
    version isa AbstractString && !isempty(version) ||
        throw(BuildError(:manifest_invalid, "manifest version must be a non-empty string"))
    for raw in files
        raw isa AbstractDict || throw(BuildError(:manifest_invalid, "manifest file entries must be tables"))
        item = Dict{String,Any}(String(k) => v for (k, v) in raw)
        get(item, "path", nothing) isa AbstractString ||
            throw(BuildError(:manifest_invalid, "manifest file path must be a string"))
        relative, full = _safe_manifest_path(abspath(String(root)), item["path"])
        size = get(item, "size", nothing)
        size isa Integer && !(size isa Bool) && size >= 0 ||
            throw(BuildError(:manifest_invalid, "manifest file size must be a non-negative integer"))
        get(item, "sha256", nothing) isa AbstractString ||
            throw(BuildError(:manifest_invalid, "manifest file hash must be a string"))
        isfile(full) || throw(BuildError(:manifest_mismatch, "manifest file is missing: $relative"))
        filesize(full) == Int(size) ||
            throw(BuildError(:manifest_mismatch, "manifest size differs: $relative"))
        _hash_file(full) == String(get(item, "sha256", "")) ||
            throw(BuildError(:manifest_mismatch, "manifest hash differs: $relative"))
    end
    expected_manifest_hash = _manifest_hash(files; schema, project, version)
    String(get(manifest, "manifest_hash", "")) == expected_manifest_hash ||
        throw(BuildError(:manifest_mismatch, "manifest index hash differs"))
    true
end

"Return structural repository problems without mutating the checkout."
function validate_repository(root::AbstractString=project_root())
    root = abspath(String(root))
    issues = String[]
    for file in _ROOT_FILES
        isfile(joinpath(root, file)) || push!(issues, "missing required file: $file")
    end
    for directory in _ROOT_DIRS
        isdir(joinpath(root, directory)) || push!(issues, "missing expected directory: $directory")
    end
    try
        project = TOML.parsefile(joinpath(root, "Project.toml"))
        haskey(project, "name") || push!(issues, "Project.toml has no package name")
        haskey(project, "version") || push!(issues, "Project.toml has no package version")
    catch error
        push!(issues, "Project.toml is invalid: " * sprint(showerror, error))
    end
    append!(issues, source_syntax_check(root))
    append!(issues, export_issues(root))
    append!(issues, fixture_check(root))
    issues
end

function build_report(root::AbstractString=project_root())
    root = abspath(String(root))
    issues = validate_repository(root)
    Dict{String,Any}("ok" => isempty(issues), "root" => root,
                     "checked_at" => string(now(UTC)), "file_count" => length(source_inventory(root)),
                     "issues" => issues, "metadata" => release_metadata(root))
end

function _json(value)
    value === nothing && return "null"
    value === true && return "true"
    value === false && return "false"
    value isa Integer && return string(value)
    value isa AbstractFloat && return string(value)
    value isa AbstractString && begin
        escaped = replace(String(value), "\\" => "\\\\", '"' => "\\\"", '\n' => "\\n",
                          '\r' => "\\r", '\t' => "\\t")
        return "\"$escaped\""
    end
    value isa AbstractVector && return "[" * join(_json.(value), ",") * "]"
    value isa AbstractDict && return "{" * join([_json(string(key)) * ":" * _json(value[key])
                                                   for key in sort!(String[string(k) for k in keys(value)])], ",") * "}"
    _json(string(value))
end

function main(args=ARGS)
    command = isempty(args) ? "check" : String(args[1])
    root = project_root()
    output = nothing
    json = false
    index = 2
    while index <= length(args)
        option = String(args[index])
        option == "--json" && (json = true; index += 1; continue)
        index += 1
        index <= length(args) || throw(BuildError(:usage, "$option requires a value"))
        option == "--root" && (root = abspath(String(args[index])))
        option == "--output" && (output = abspath(String(args[index])))
        index += 1
    end
    if command == "check"
        report = build_report(root)
        println(json ? _json(report) : (report["ok"] ? "build check: ok" : join(report["issues"], "\n")))
        return report["ok"] ? 0 : 1
    elseif command == "inventory"
        println(join(source_inventory(root), "\n"))
    elseif command == "manifest"
        destination = output === nothing ? joinpath(root, "build-manifest.toml") : output
        write_manifest(destination, artifact_manifest(root))
        println(destination)
    elseif command == "verify"
        path = output === nothing ? joinpath(root, "build-manifest.toml") : output
        verify_manifest(path; root)
        println("build manifest: verified")
    elseif command == "metadata"
        metadata = release_metadata(root)
        if output === nothing
            println(json ? _json(metadata) : join([string(key, "=", metadata[key]) for key in sort!(collect(keys(metadata)))], "\n"))
        else
            write_manifest(output, metadata)
            println(output)
        end
    else
        throw(BuildError(:usage, "unknown build command: $command (use check, inventory, manifest, verify, or metadata)"))
    end
    0
end

end

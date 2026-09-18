"User-scoped deployment of the JuliaShell runtime and session services."
module Deploy

using Dates
using ..Build

const _SERVICE_FILES = ("julia-shelld.service", "julia-shell-ui.service", "julia-shell.target")

struct DeploymentError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::DeploymentError) = print(io, error.message)

function deployment_paths(; env=ENV, home=get(env, "HOME", homedir()))
    config = get(env, "XDG_CONFIG_HOME", joinpath(home, ".config"))
    data = get(env, "XDG_DATA_HOME", joinpath(home, ".local", "share"))
    Dict{String,String}(
        "install" => joinpath(data, "julia-shell", "install"),
        "bin" => joinpath(home, ".local", "bin"),
        "systemd" => joinpath(config, "systemd", "user"),
        "repository" => joinpath(config, "julia-shell", "repository"),
    )
end

function _plan(source::String; env=ENV)
    paths = deployment_paths(; env)
    files = Build.source_inventory(source)
    Dict{String,Any}("source" => source, "paths" => paths, "files" => files,
                     "service_files" => collect(_SERVICE_FILES))
end

function _write_wrapper(path, content)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, content)
        endswith(content, "\n") || write(io, '\n')
    end
    chmod(path, 0o755)
end

function _wrapper(root::String, daemon::Bool)
    entry = daemon ? """
repo = get(ENV, "JULIA_SHELL_REPO", joinpath(get(ENV, "HOME", homedir()), ".config", "julia-shell", "repository"))
socket_path = get(ENV, "JULIA_SHELL_SOCKET", nothing)
JuliaShell.run_daemon(repo; socket_path)
""" : """
exit(JuliaShell.main())
"""
    "#!/usr/bin/env julia\nusing Pkg\nPkg.activate($(repr(root)))\nusing JuliaShell\n$entry"
end

function _service(source::String, name::String, paths)
    content = read(joinpath(source, "packaging", name), String)
    home = dirname(dirname(paths["bin"]))
    content = replace(content, "%h/.local/bin/julia-shelld" => joinpath(paths["bin"], "julia-shelld"))
    content = replace(content, "%h/.config/julia-shell/quickshell/Main.qml" => joinpath(paths["install"], "quickshell", "Main.qml"))
    content = replace(content, "%h/.config/julia-shell/repository" => paths["repository"])
    content
end

"Copy the validated project into a user-scoped immutable-ish install tree."
function deploy!(source::AbstractString=Build.project_root(); env=ENV, yes=false)
    yes || throw(DeploymentError(:confirmation_required, "deployment requires explicit confirmation; pass yes=true or --yes"))
    source = Build.project_root(source)
    issues = Build.validate_repository(source)
    isempty(issues) || throw(DeploymentError(:build_invalid, "cannot deploy an invalid project: " * join(issues, "; ")))
    paths = deployment_paths(; env)
    install = paths["install"]
    parent = dirname(install)
    mkpath(parent)
    stage = mktempdir(parent)
    backup = nothing
    try
        for relative in Build.source_inventory(source)
            destination = joinpath(stage, relative)
            mkpath(dirname(destination))
            cp(joinpath(source, relative), destination; force=true)
        end
        bin_stage = joinpath(stage, "bin")
        _write_wrapper(joinpath(bin_stage, "julia-shell"), _wrapper(install, false))
        _write_wrapper(joinpath(bin_stage, "julia-shelld"), _wrapper(install, true))
        if ispath(install)
            backup = install * ".previous-" * string(round(Int, time()))
            mv(install, backup; force=false)
        end
        mv(stage, install; force=false)
        mkpath(paths["bin"])
        for name in ("julia-shell", "julia-shelld")
            staged = joinpath(install, "bin", name)
            destination = joinpath(paths["bin"], name)
            cp(staged, destination; force=true)
            chmod(destination, 0o755)
        end
        mkpath(paths["systemd"])
        for name in _SERVICE_FILES
            open(joinpath(paths["systemd"], name), "w") do io
                write(io, _service(source, name, paths))
            end
        end
        Dict{String,Any}("ok" => true, "installed" => install, "bin" => paths["bin"],
                         "systemd" => paths["systemd"], "deployed_at" => string(now(UTC)))
    catch error
        isdir(stage) && rm(stage; recursive=true, force=true)
        backup !== nothing && !ispath(install) && ispath(backup) && mv(backup, install; force=false)
        error isa DeploymentError && rethrow()
        throw(DeploymentError(:deployment_failed, sprint(showerror, error)))
    end
end

function deployment_plan(source::AbstractString=Build.project_root(); env=ENV)
    _plan(Build.project_root(source); env)
end

end

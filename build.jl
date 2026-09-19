#!/usr/bin/env julia

# JuliaShell's Build.jl-powered development build entry point.
#
# Run with the dedicated build environment so the build graph stays out of the
# runtime package environment:
#
#     julia --project=build build.jl [target] [--root PATH] [--output PATH]
using Build

# Keep repository validation separate from the external build graph package.
module JuliaShellAudit
include(joinpath(@__DIR__, "src", "BuildValidation.jl"))
end
const Audit = JuliaShellAudit.BuildValidation

function _usage()
    println("usage: julia --project=build build.jl [all|check|test|inventory|manifest|verify|metadata|deploy|clean] [--root PATH] [--output PATH] [--json] [--dry-run] [--quiet]")
end

function _arguments(args)
    target = "all"
    root = @__DIR__
    output = nothing
    json = false
    dry_run = false
    verbose = true
    index = 1
    if index <= length(args) && !startswith(args[index], "-")
        target = String(args[index])
        index += 1
    end
    while index <= length(args)
        option = String(args[index])
        if option == "--root" || option == "--output"
            index += 1
            index <= length(args) || throw(ArgumentError("$option requires a value"))
            option == "--root" ? (root = abspath(String(args[index]))) : (output = abspath(String(args[index])))
        elseif option == "--json"
            json = true
        elseif option == "--dry-run"
            dry_run = true
        elseif option == "--quiet"
            verbose = false
        elseif option == "--help" || option == "-h"
            _usage()
            return nothing
        else
            throw(ArgumentError("unknown option: $option"))
        end
        index += 1
    end
    (target=target, root=root, output=output, json=json, dry_run=dry_run, verbose=verbose)
end

function _print_check(root, json)
    report = Audit.build_report(root)
    if json
        println(Audit._json(report))
    elseif report["ok"]
        println("build check: ok")
    else
        println(join(report["issues"], "\n"))
        throw(ErrorException("build check failed"))
    end
end

function _print_metadata(root, output, json)
    metadata = Audit.release_metadata(root)
    if output === nothing
        println(json ? Audit._json(metadata) : join([string(key, "=", metadata[key]) for key in sort!(collect(keys(metadata)))], "\n"))
    else
        Audit.write_manifest(output, metadata)
        println(output)
    end
end

function build_context(options)
    ctx = Build.BuildContext(workdir=options.root, dry_run=options.dry_run, verbose=options.verbose)
    manifest_path = options.output === nothing ? joinpath(tempdir(), "julia-shell-build-manifest.toml") : options.output
    project_flag = "--project=$(options.root)"
    test_command = `$(Base.julia_cmd()) --startup-file=no --history-file=no $project_flag -e "using Pkg; Pkg.test()"`

    Build.add_target!(ctx, "check"; virtual=true, recipe=(_, _) -> _print_check(options.root, options.json))
    Build.add_target!(ctx, "test"; virtual=true, recipe=(_, _) -> test_command)
    Build.add_target!(ctx, "inventory"; virtual=true,
                      recipe=(_, _) -> println(join(Audit.source_inventory(options.root), "\n")))
    Build.add_target!(ctx, manifest_path; deps=Audit.source_inventory(options.root), recipe=(build, _) -> begin
        build.dry_run || Audit.write_manifest(manifest_path, Audit.artifact_manifest(options.root))
    end)
    Build.add_target!(ctx, "manifest"; deps=[manifest_path], virtual=true,
                      recipe=(_, _) -> println(manifest_path))
    Build.add_target!(ctx, "verify"; virtual=true, recipe=(_, _) -> begin
        Audit.verify_manifest(manifest_path; root=options.root)
        println("build manifest: verified")
    end)
    Build.depends!(ctx, "verify", "manifest")
    Build.add_target!(ctx, "metadata"; virtual=true,
                      recipe=(_, _) -> _print_metadata(options.root, options.output, options.json))
    deployment = "using JuliaShell; JuliaShell.Deploy.deploy!($(repr(options.root)); yes=true)"
    Build.add_target!(ctx, "deploy"; virtual=true,
                      recipe=(_, _) -> `$(Base.julia_cmd()) --startup-file=no --history-file=no --project=$(options.root) -e $deployment`)
    Build.add_target!(ctx, "all"; deps=["check", "test", "verify"], virtual=true)
    ctx
end

function main(args=ARGS)
    options = _arguments(args)
    options === nothing && return 0
    ctx = build_context(options)
    if options.target == "clean"
        manifest_path = options.output === nothing ? joinpath(tempdir(), "julia-shell-build-manifest.toml") : options.output
        Build.clean!(ctx, manifest_path)
    else
        Build.build!(ctx, options.target)
    end
    return 0
end

try
    exit(main())
catch error
    showerror(stderr, error, catch_backtrace())
    println(stderr)
    exit(1)
end

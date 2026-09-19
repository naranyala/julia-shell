using Test
using Build

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const BUILD_SCRIPT = joinpath(ROOT, "build.jl")
const BUILD_PROJECT = joinpath(ROOT, "build")

function run_build(args...)
    command = `$(Base.julia_cmd()) --startup-file=no --history-file=no --project=$BUILD_PROJECT $BUILD_SCRIPT $(collect(args))`
    read(command, String)
end

@testset "JuliaShell Build.jl integration" begin
    @test occursin("build check: ok", run_build("check", "--quiet"))
    inventory = run_build("inventory", "--quiet")
    @test occursin("src/JuliaShell.jl", inventory)
    @test occursin("build.jl", inventory)

    mktempdir() do directory
        manifest = joinpath(directory, "manifest.toml")
        @test strip(run_build("manifest", "--output", manifest, "--quiet")) == manifest
        @test isfile(manifest)
        @test strip(run_build("manifest", "--output", manifest, "--quiet")) == manifest
        @test occursin("build manifest: verified", run_build("verify", "--output", manifest, "--quiet"))
        @test strip(run_build("clean", "--output", manifest, "--quiet")) == ""
        @test !ispath(manifest)
        @test strip(run_build("manifest", "--output", manifest, "--dry-run", "--quiet")) == manifest
        @test !ispath(manifest)
    end

    context = Build.BuildContext(verbose=false)
    Build.add_target!(context, "generated"; recipe=(ctx, target) ->
                      write(joinpath(ctx.workdir, target.name), "ok"))
    @test Build.build!(context, "generated") === context
end

using Test

# Build.jl must remain usable without loading the runtime package.
module StandaloneBuildTools
include(joinpath(@__DIR__, "..", "src", "Build.jl"))
end

@testset "standalone build validation" begin
    build = StandaloneBuildTools.Build
    mktempdir() do root
        mkpath(joinpath(root, "src"))
        write(joinpath(root, "Project.toml"), "name = \"Fixture\"\nversion = \"1.0.0\"\n")
        write(joinpath(root, "src", "Good.jl"), "module Good\nend\n")
        @test "src/Good.jl" in build.source_inventory(root)
        manifest = build.artifact_manifest(root)
        manifest_path = joinpath(root, "manifest.toml")
        build.write_manifest(manifest_path, manifest)
        @test build.verify_manifest(manifest_path; root)
        @test isempty(build.source_syntax_check(root))
        write(joinpath(root, "src", "Broken.jl"), "module Broken\n")
        @test !isempty(build.source_syntax_check(root))
        rm(joinpath(root, "src", "Broken.jl"))

        write(joinpath(root, "src", "JuliaShell.jl"),
              "module JuliaShell\nexport defined_api, missing_api\ndefined_api() = true\nend\n")
        @test build.exported_symbols(root) == ["defined_api", "missing_api"]
        @test build.export_issues(root) == ["exported symbol is not defined in source tree: missing_api"]

        @test_throws build.BuildError build.artifact_manifest(root; files=["../outside"])
        outside = joinpath(dirname(root), "outside-" * basename(root))
        write(outside, "secret")
        symlink(outside, joinpath(root, "src", "outside-link"))
        @test_throws build.BuildError build.artifact_manifest(root; files=["src/outside-link"])

        tampered = deepcopy(manifest)
        tampered["project"] = "Other"
        build.write_manifest(manifest_path, tampered)
        @test_throws build.BuildError build.verify_manifest(manifest_path; root)

        malformed = deepcopy(manifest)
        malformed["files"] = Any["not-a-table"]
        build.write_manifest(manifest_path, malformed)
        @test_throws build.BuildError build.verify_manifest(manifest_path; root)

        deep = joinpath(root, "test", "fixtures", "deep")
        mkpath(deep)
        @test build.project_root(deep) == root
    end
end

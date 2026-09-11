using Test
using JuliaShell

function test_env(root)
    home = joinpath(root, "home")
    env = Dict{String,String}(
        "HOME" => home,
        "XDG_CONFIG_HOME" => joinpath(home, ".config"),
        "XDG_DATA_HOME" => joinpath(home, ".local", "share"),
        "XDG_STATE_HOME" => joinpath(root, "state"),
        "XDG_CACHE_HOME" => joinpath(root, "cache"),
        "XDG_RUNTIME_DIR" => joinpath(root, "run"),
    )
    foreach(mkpath, values(env))
    env
end

@testset "profile schema and round trip" begin
    mktempdir() do root
        env = test_env(root)
        repo = joinpath(root, "repo")
        init_repository(repo)
        profile_path = repository_profile_path(repo)
        profile = Profile("personal";
            dock=Dock(pins=[Pin("org.example.Editor.desktop"; position=20, label="Editor")]),
            dotfiles=[DotfileEntry("editor", "files/editor", raw"${XDG_CONFIG_HOME}/editor"; mode="copy")])
        save_profile(profile_path, profile)
        loaded = load_profile(profile_path)
        @test loaded.name == "personal"
        @test loaded.dock.pins[1].desktop_id == "org.example.Editor.desktop"
        @test loaded.dotfiles[1].mode == "copy"
        @test_throws ValidationError profile_from_dict(Dict("schema" => 99); source_path="bad.toml")
    end
end

@testset "path safety and protocol" begin
    mktempdir() do root
        env = test_env(root)
        @test is_path_within(joinpath(env["HOME"], "a"), env["HOME"])
        @test !is_path_within(joinpath(env["HOME"] * "-other"), env["HOME"])
        @test_throws JuliaShellError safe_target_path("/etc/passwd"; env=env)
        @test_throws JuliaShellError resolve_variables(raw"${PATH}"; env=env)
        message = Dict{String,Any}("v" => 1, "id" => "abc", "method" => "status",
                                   "params" => Dict("n" => 4, "ok" => true))
        @test decode_message(encode_message(message))["method"] == "status"
        @test decode_message(encode_message(message))["params"]["n"] == 4
        @test_throws JuliaShellError decode_message("{\"v\":2}")
        @test validate_protocol_request(protocol_request("abc", "status"))["method"] == "status"
        @test_throws JuliaShellError validate_protocol_request(Dict("v" => 1, "id" => "abc", "method" => "pins.pin", "params" => Dict{String,Any}()))
        @test_throws JuliaShellError decode_message("not-json")
    end
end

@testset "safe deployment and conflict planning" begin
    mktempdir() do root
        env = test_env(root)
        repo = joinpath(root, "repo")
        snapshots = joinpath(root, "snapshots")
        init_repository(repo)
        source = joinpath(repo, "files", "editor.conf")
        write(source, "first\n")
        target = raw"${XDG_CONFIG_HOME}/editor.conf"
        save_profile(repository_profile_path(repo), Profile("personal";
            dotfiles=[DotfileEntry("editor", "files/editor.conf", target; mode="copy")]))
        first_plan = plan(repo; env=env)
        @test first_plan.actions[1].kind == :create
        result = apply!(first_plan; repo=repo, env=env, yes=true, snapshot_root=snapshots)
        @test result.phase == :verified
        deployed = joinpath(env["XDG_CONFIG_HOME"], "editor.conf")
        @test read(deployed, String) == "first\n"
        @test plan(repo; env=env).actions[1].kind == :no_op
        snapshots_list = JuliaShell.list_snapshots(root=snapshots)
        @test length(snapshots_list) == 1
        @test verify_snapshot(snapshots_list[1]["path"])

        write(source, "repository change\n")
        write(deployed, "local change\n")
        conflicting = plan(repo; env=env)
        @test conflicting.actions[1].kind == :conflict
        @test_throws JuliaShellError apply!(conflicting; repo=repo, env=env, yes=true, snapshot_root=snapshots)
        @test read(deployed, String) == "local change\n"
    end
end

@testset "snapshot restore and pins" begin
    mktempdir() do root
        env = test_env(root)
        repo = joinpath(root, "repo")
        snapshots = joinpath(root, "snapshots")
        init_repository(repo)
        source = joinpath(repo, "files", "one")
        write(source, "one\n")
        deployed_target = raw"${XDG_CONFIG_HOME}/one"
        save_profile(repository_profile_path(repo), Profile("personal";
            dotfiles=[DotfileEntry("one", "files/one", deployed_target; mode="copy")]))
        apply!(plan(repo; env=env); repo=repo, env=env, yes=true, snapshot_root=snapshots)
        deployed = joinpath(env["XDG_CONFIG_HOME"], "one")
        recovery = create_snapshot(plan(repo; env=env).actions; root=snapshots, env=env)
        write(deployed, "broken\n")
        restored = restore_snapshot(recovery.path; yes=true, env=env, snapshot_root=snapshots)
        @test restored.phase == :verified
        @test read(deployed, String) == "one\n"

        @test pin!(repo, "org.example.First.desktop"; env=env, request_id="pin-1")["revision"] == 1
        duplicate_request = pin!(repo, "org.example.First.desktop"; env=env, request_id="pin-1")
        @test duplicate_request["revision"] == 1
        @test length(load_profile(repository_profile_path(repo)).dock.pins) == 1
        @test_throws JuliaShellError pin!(repo, "org.example.Second.desktop"; env=env, expected_revision=0)
        pin!(repo, "org.example.Second.desktop"; env=env, request_id="pin-2")
        reorder!(repo, 2, 1; env=env, expected_revision=2, request_id="move-1")
        @test [pin.desktop_id for pin in load_profile(repository_profile_path(repo)).dock.pins] ==
              ["org.example.Second.desktop", "org.example.First.desktop"]
        lock_path = joinpath(env["XDG_STATE_HOME"], "julia-shell", "profiles",
                             JuliaShell._repository_key(repo), "mutation.lock")
        @test isfile(lock_path)
    end
end

@testset "desktop identity resolution" begin
    mktempdir() do root
        applications = joinpath(root, "applications")
        mkpath(applications)
        write(joinpath(applications, "editor.desktop"), "[Desktop Entry]\nName=Editor\nExec=/usr/bin/editor %U\nStartupWMClass=Editor\nIcon=editor\n")
        index = scan_desktop_entries(; dirs=[applications])
        resolved = resolve_application("editor"; entries=index)
        @test resolved["status"] == "resolved"
        @test resolved["desktop_id"] == "editor.desktop"
        @test resolved["score"] == 80
        @test resolve_application("missing"; entries=index)["status"] == "missing"
        @test JuliaShell._exec_basename("\"/opt/My App/editor\" --new-window %U") == "editor"
        @test JuliaShell._exec_basename("/usr/bin/editor %U") == "editor"
    end
end

@testset "desktop entries module" begin
    mktempdir() do root
        user_apps = joinpath(root, "user", "applications")
        system_apps = joinpath(root, "system", "applications")
        mkpath(joinpath(user_apps, "nested"))
        mkpath(system_apps)
        entry_path = joinpath(user_apps, "nested", "editor.desktop")
        write(entry_path, """[Desktop Entry]
Type=Application
Name=Editor
Name[fr]=Éditeur
GenericName=Text\\sEditor
Icon=editor
Categories=Utility;TextEditor;
MimeType=text/plain;text/markdown;
Exec=/usr/bin/editor --title \"%c\" %U %i
Terminal=false
""")
        write(joinpath(user_apps, "hidden.desktop"), """[Desktop Entry]
Type=Application
Name=Hidden
NoDisplay=true
Exec=/usr/bin/hidden
""")
        write(joinpath(system_apps, "hidden.desktop"), """[Desktop Entry]
Type=Application
Name=System Hidden
Exec=/usr/bin/system-hidden
""")
        write(joinpath(user_apps, "broken.desktop"), """[Desktop Entry]
Type=Application
Name=Broken
Exec=/usr/bin/broken %x
""")
        mkpath(joinpath(system_apps, "nested"))
        write(joinpath(system_apps, "nested", "editor.desktop"), """[Desktop Entry]
Type=Application
Name=System Editor
Exec=/usr/bin/system-editor
""")

        env = Dict{String,String}("LANG" => "fr_FR.UTF-8")
        entry = parse_desktop_entry(entry_path; env=env, desktop_id="nested/editor.desktop")
        @test entry.name == "Éditeur"
        @test entry.generic_name == "Text Editor"
        @test entry.categories == ["Utility", "TextEditor"]
        @test entry.mime_types == ["text/plain", "text/markdown"]
        @test entry.exec_arguments == ["/usr/bin/editor", "--title", "%c", "%U", "%i"]
        @test launch_arguments(entry; urls=["https://example.test/a", "https://example.test/b"]) ==
              ["/usr/bin/editor", "--title", "Éditeur", "https://example.test/a", "https://example.test/b", "--icon", "editor"]
        @test exec_arguments("/usr/bin/editor %f"; files=["/tmp/a;touch"]) == ["/usr/bin/editor", "/tmp/a;touch"]
        @test parse_exec("\"/opt/My App/editor\" --name \"hello world\" %U") ==
              ["/opt/My App/editor", "--name", "hello world", "%U"]
        @test parse_exec(raw"/opt/My\ App/editor %U") == ["/opt/My App/editor", "%U"]
        @test exec_arguments("/usr/bin/editor %f") == ["/usr/bin/editor"]
        @test_throws ArgumentError exec_arguments("/usr/bin/editor %x")

        index = discover_applications(; dirs=[user_apps, system_apps], env=env)
        @test haskey(index, "nested/editor.desktop")
        @test index["nested/editor.desktop"].name == "Éditeur"
        @test !haskey(index, "hidden.desktop")
        @test haskey(discover_applications(; dirs=[user_apps], include_hidden=true), "hidden.desktop")
        @test !haskey(discover_applications(; dirs=[user_apps, system_apps]), "hidden.desktop")
        @test resolve_application("nested/editor"; entries=index)["desktop_id"] == "nested/editor.desktop"
        @test resolve_application("editor"; entries=index, aliases=Dict("editor" => "nested/editor.desktop"))["score"] == 95
    end
end

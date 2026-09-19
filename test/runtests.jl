using Test
using TOML
using JuliaShell

using TOML

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

@testset "systemd and Wayland runtime boundaries" begin
    @test systemd_available() isa Bool
    @test watchdog_interval_seconds(env=Dict("WATCHDOG_USEC" => "2000000"), pid=42) == 1.0
    @test watchdog_interval_seconds(env=Dict("WATCHDOG_USEC" => "2000000",
                                                "WATCHDOG_PID" => "7"), pid=42) === nothing
    @test watchdog_interval_seconds(env=Dict("WATCHDOG_USEC" => "invalid")) === nothing
    unit = JuliaShell._parse_systemctl_show("julia-shelld.service", """
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
Description=Julia Shell
""")
    @test unit.active_state == "active"
    @test unit.sub_state == "running"
    @test unit.description == "Julia Shell"
    @test JuliaShell._unit_name("julia-shell@personal.service") == "julia-shell@personal.service"
    @test_throws ArgumentError JuliaShell._unit_name("--system")

    @test wayland_available() isa Bool
    capabilities = wayland_capabilities()
    @test "ext_session_lock_manager_v1" in capabilities["session"]
    @test "ext_foreign_toplevel_list_v1" in capabilities["desktop"]
    disconnected = WaylandDisplay(C_NULL, "test", -1, false, nothing)
    @test_throws JuliaShellError wayland_fd(disconnected)
    @test disconnect_wayland!(disconnected) === nothing
    mktempdir() do root
        env = Dict("XDG_RUNTIME_DIR" => root, "WAYLAND_DISPLAY" => "missing-wayland")
        @test connect_wayland(; env, required=false) === nothing
    end
end

@testset "runtime provider coordination" begin
    coordinator = SessionCoordinator()
    audio = FakeShellProvider("audio";
        capabilities=["audio.volume", "audio.mute"], state=Dict("volume" => 0.4))
    register_action!(audio, "set-volume") do parameters
        audio.state["volume"] = parameters["volume"]
        push_provider_event!(audio, :volume_changed; payload=Dict("volume" => parameters["volume"]))
        copy(audio.state)
    end
    @test register_provider!(coordinator, audio) === audio
    @test_throws JuliaShellError register_provider!(coordinator, audio)
    runtime_received = ProviderEvent[]
    runtime_subscription = subscribe_runtime!(coordinator) do event
        push!(runtime_received, event)
    end
    @test runtime_subscription == 1
    @test invoke_provider!(coordinator, "audio", "set-volume", Dict("volume" => 0.75))["volume"] == 0.75
    received = ProviderEvent[]
    subscription = subscribe_provider!(audio) do event
        push!(received, event)
    end
    @test subscription == 1
    push_provider_event!(audio, :manual_check; payload=Dict("ok" => true))
    @test received[1].kind == :manual_check
    @test unsubscribe_provider!(audio, subscription)
    @test !unsubscribe_provider!(audio, subscription)
    @test length(runtime_received) >= 1
    @test unsubscribe_runtime!(coordinator, runtime_subscription)
    @test !unsubscribe_runtime!(coordinator, runtime_subscription)
    snapshot = runtime_snapshot(coordinator)
    @test snapshot["health"] == "ready"
    @test snapshot["providers"][1]["capabilities"] == ["audio.mute", "audio.volume"]
    events = drain_runtime_events!(coordinator)
    @test [event.kind for event in events] == [:provider_registered, :action_completed, :volume_changed, :manual_check]
    @test isempty(drain_runtime_events!(coordinator))
    @test unregister_provider!(coordinator, "audio")
    @test !unregister_provider!(coordinator, "audio")
    @test_throws JuliaShellError invoke_provider!(coordinator, "audio", "set-volume")

    degraded = FakeShellProvider("network"; health=:degraded, message="reconnecting")
    register_provider!(coordinator, degraded)
    @test runtime_snapshot(coordinator)["health"] == "degraded"
    @test_throws ArgumentError ProviderHealth("bad", :broken)
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
        escaped = Dict{String,Any}("v" => 1, "text" => "quote \" slash \\ newline\n café 😀",
                                   "values" => Any[nothing, false, -4, 2.5e2])
        decoded_escaped = decode_message(encode_message(escaped))
        @test decoded_escaped["text"] == escaped["text"]
        @test decoded_escaped["values"] == escaped["values"]
        @test_throws JuliaShellError decode_message("{\"v\":2}")
        @test_throws JuliaShellError decode_message("{\"v\":true}")
        @test_throws JuliaShellError decode_message("{\"v\":1.0}")
        @test validate_protocol_request(protocol_request("abc", "status"))["method"] == "status"
        @test_throws JuliaShellError validate_protocol_request(Dict("v" => 1, "id" => "abc", "method" => "pins.pin", "params" => Dict{String,Any}()))
        @test_throws JuliaShellError decode_message("not-json")
        @test_throws JuliaShellError decode_message("{\"v\":1,\"text\":\"\\q\"}")
        @test_throws JuliaShellError decode_message("[]")
        for (method, params) in (
            ("pins.pin", Dict("desktop_id" => "app.desktop", "position" => true)),
            ("pins.pin", Dict("desktop_id" => "app.desktop", "if_revision" => true)),
            ("pins.reorder", Dict("from" => true, "to" => 2)),
            ("pins.reorder", Dict("from" => 1, "to" => true)),
        )
            @test_throws JuliaShellError validate_protocol_request(protocol_request("strict", method, params))
        end
        stream = IOBuffer(encode_message(message) * "\n" * encode_message(protocol_request("next", "status")))
        decoded = JuliaShell.jsonl_decode_stream(stream; max_messages=2, max_bytes=512)
        @test [item["id"] for item in decoded] == ["abc", "next"]
        @test_throws JuliaShell.CodecError JuliaShell.jsonl_decode_stream(
            IOBuffer(encode_message(message) * encode_message(message)); max_messages=1)
        @test_throws JuliaShell.CodecError JuliaShell.jsonl_decode_stream(
            IOBuffer(encode_message(message)); max_bytes=4)
        @test isempty(JuliaShell.jsonl_decode_stream(IOBuffer("\n \n")))
        @test_throws JuliaShell.CodecError JuliaShell.jsonl_decode_stream(
            IOBuffer(encode_message(message) * encode_message(message)); max_messages=1)
    end
end

@testset "CLI output adapters" begin
    @test JuliaShell._json_encode(Dict("v" => 1, "ok" => true)) == "{\"ok\":true,\"v\":1}"
    @test JuliaShell._human_result(Dict("count" => 2)) == "count: 2"
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

        unpin_result = unpin!(repo, "org.example.First.desktop"; env=env, expected_revision=3, request_id="unpin-1")
        @test unpin_result["revision"] == 4
        @test length(load_profile(repository_profile_path(repo)).dock.pins) == 1
        @test load_profile(repository_profile_path(repo)).dock.pins[1].desktop_id == "org.example.Second.desktop"
        duplicate_unpin = unpin!(repo, "org.example.First.desktop"; env=env, request_id="unpin-1")
        @test duplicate_unpin["revision"] == 4
        @test_throws JuliaShellError unpin!(repo, "org.example.First.desktop"; env=env)
        @test_throws JuliaShellError unpin!(repo, "org.example.Second.desktop"; env=env, expected_revision=0)
    end
end

@testset "journal recovery" begin
    mktempdir() do root
        env = test_env(root)
        repo = joinpath(root, "repo")
        snapshots = joinpath(root, "snapshots")
        init_repository(repo)
        source = joinpath(repo, "files", "data.conf")
        write(source, "original\n")
        save_profile(repository_profile_path(repo), Profile("personal";
            dotfiles=[DotfileEntry("data", "files/data.conf", raw"${XDG_CONFIG_HOME}/data.conf"; mode="copy")]))
        first_plan = plan(repo; env=env)
        apply!(first_plan; repo=repo, env=env, yes=true, snapshot_root=snapshots)
        target = joinpath(env["XDG_CONFIG_HOME"], "data.conf")
        @test read(target, String) == "original\n"
        stage = target * ".julia-shell-stage-test-recovery-data"
        backup = target * ".julia-shell-backup-test-recovery-data"
        write(backup, "backup-content\n")
        write(stage, "staged-content\n")
        journal_dir = joinpath(env["XDG_STATE_HOME"], "julia-shell", "journal")
        mkpath(journal_dir)
        journal = Dict{String,Any}(
            "schema" => 1, "id" => "test-recovery", "operation" => "apply",
            "profile" => "personal", "plan_hash" => "abc123",
            "phase" => "committed",
            "steps" => [Dict{String,Any}(
                "id" => "data", "target" => target,
                "stage" => stage, "backup" => backup,
                "had_target" => true, "status" => "committed"
            )],
            "created_at" => "2026-01-01T00:00:00Z"
        )
        JuliaShell._write_journal(joinpath(journal_dir, "test-recovery.toml"), journal)
        write(target, "corrupted-by-crash\n")
        result = recover_journals!(; env=env)
        @test length(result["recovered"]) == 1
        @test isempty(result["failed"])
        recovered_journal = TOML.parsefile(joinpath(journal_dir, "test-recovery.toml"))
        @test recovered_journal["phase"] == "rolled_back"
        @test haskey(recovered_journal, "recovered_at")
        @test read(target, String) == "backup-content\n"
        @test !isfile(stage)
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

@testset "desktop icon resolution" begin
    mktempdir() do root
        icon_root = joinpath(root, "data")
        icon = joinpath(icon_root, "icons", "hicolor", "48x48", "apps", "editor.svg")
        mkpath(dirname(icon))
        write(icon, "<svg/>")
        env = Dict{String,String}("HOME" => root, "XDG_DATA_HOME" => icon_root,
                                  "XDG_DATA_DIRS" => joinpath(root, "system"))
        @test resolve_icon("editor"; env) == icon
        @test resolve_icon(icon; env) == icon
        @test resolve_icon("missing"; env) === nothing
    end
end

@testset "internal build utilities" begin
    mktempdir() do root
        for directory in ("src", "test", "docs", "bin", "packaging", "quickshell")
            mkpath(joinpath(root, directory))
        end
        write(joinpath(root, "Project.toml"), "name = \"Fixture\"\nversion = \"1.2.3\"\n")
        for file in ("Manifest.toml", "README.md", "TODOS.md")
            write(joinpath(root, file), file)
        end
        write(joinpath(root, "src", "Main.jl"), "module Main\nend\n")
        manifest = BuildValidation.artifact_manifest(root)
        @test manifest["version"] == "1.2.3"
        @test manifest["files"][1]["path"] == "Manifest.toml"
        manifest_path = joinpath(root, "build-manifest.toml")
        BuildValidation.write_manifest(manifest_path, manifest)
        @test BuildValidation.verify_manifest(manifest_path; root)
        @test isempty(BuildValidation.source_syntax_check(root))
        @test isempty(BuildValidation.fixture_check(root))
        @test isempty(BuildValidation.exported_symbols(root))
        @test isempty(BuildValidation.export_issues(root))
        @test BuildValidation.release_metadata(root)["version"] == "1.2.3"
        write(joinpath(root, "src", "Main.jl"), "changed\n")
        @test_throws BuildValidation.BuildError BuildValidation.verify_manifest(manifest_path; root)
        rewritten = TOML.parsefile(manifest_path)
        rewritten["manifest_hash"] = "tampered"
        open(manifest_path, "w") do io
            TOML.print(io, rewritten)
        end
        @test_throws BuildValidation.BuildError BuildValidation.verify_manifest(manifest_path; root)
        @test isempty(BuildValidation.validate_repository(root))
        write(joinpath(root, "src", "Broken.jl"), "module Broken\n")
        @test !isempty(BuildValidation.source_syntax_check(root))
    end
end

@testset "user-scoped deployment plan" begin
    mktempdir() do root
        env = Dict{String,String}("HOME" => joinpath(root, "home"),
                                  "XDG_CONFIG_HOME" => joinpath(root, "home", ".config"),
                                  "XDG_DATA_HOME" => joinpath(root, "home", ".local", "share"))
        paths = Deploy.deployment_paths(; env)
        @test endswith(paths["install"], joinpath("julia-shell", "install"))
        @test Deploy.deployment_plan(; env)["service_files"] == ["julia-shelld.service", "julia-shell-ui.service", "julia-shell.target"]
        @test_throws Deploy.DeploymentError Deploy.deploy!(BuildValidation.project_root(); env, yes=false)
        result = Deploy.deploy!(BuildValidation.project_root(); env, yes=true)
        @test result["ok"]
        @test isfile(joinpath(paths["install"], "Project.toml"))
        @test isfile(joinpath(paths["bin"], "julia-shell"))
        @test occursin(paths["install"], read(joinpath(paths["bin"], "julia-shell"), String))
        @test occursin(paths["install"], read(joinpath(paths["systemd"], "julia-shell-ui.service"), String))
    end
end

@testset "compositor contract and canonical projection" begin
    mktempdir() do root
        env = test_env(root)
        repo = joinpath(root, "repo")
        init_repository(repo)
        profile = Profile("personal";
            dock=Dock(pins=[Pin("editor.desktop"; position=10)]))
        save_profile(repository_profile_path(repo), profile)

        apps = ApplicationIndex()
        apps["editor.desktop"] = DesktopEntry("editor.desktop", "Editor", nothing, "accessories-text-editor",
            nothing, "/usr/bin/editor", ["/usr/bin/editor"], "editor", ["Utility"], String[],
            "/tmp/editor.desktop", false, false, false, "Application")
        apps["terminal.desktop"] = DesktopEntry("terminal.desktop", "Terminal", nothing, "utilities-terminal",
            nothing, "/usr/bin/terminal", ["/usr/bin/terminal"], "terminal", ["System"], String[],
            "/tmp/terminal.desktop", false, false, false, "Application")
        fake = FakeCompositor(
            outputs=[OutputState("HDMI-A-1"; width=1920, height=1080, focused=true),
                     OutputState("DP-1"; width=2560, height=1440)],
            toplevels=[ToplevelState("window-1", "editor"; title="notes.md", output="HDMI-A-1",
                                     workspace="1", focused=true),
                       ToplevelState("window-2", "terminal"; title="shell", output="HDMI-A-1",
                                     workspace="1")])
        state = state_projection(profile; repo, env, compositor=fake, entries=apps)
        @test state["schema"] == 1
        @test state["statusbar"]["schema"] == STATUSBAR_SCHEMA
        @test state["statusbar"]["health"] == "ready"
        @test state["statusbar"]["pinned"] == 1
        @test state["statusbar"]["running"] == 2
        @test state["statusbar"]["focused"] == 1
        @test state["statusbar"]["urgent"] == 0
        @test state["health"] == "ready"
        @test state["dock"]["selected_outputs"] == ["HDMI-A-1"]
        @test [item["desktop_id"] for item in state["items"]] == ["editor.desktop", "terminal.desktop"]
        @test state["items"][1]["pinned"]
        @test state["items"][1]["focused"]
        @test state["items"][1]["instance_count"] == 1
        @test !state["items"][2]["pinned"]
        @test state["workspace_states"][1]["window_count"] == 2
        compositor_received = CompositorEvent[]
        compositor_subscription = subscribe_compositor!(fake) do event
            push!(compositor_received, event)
        end
        @test focus_toplevel!(fake, "window-2")
        @test only(filter(window -> window.ref.id == "window-2", compositor_toplevels(fake))).focused
        @test only(compositor_received).kind == :focus_changed
        @test unsubscribe_compositor!(fake, compositor_subscription)
        @test !unsubscribe_compositor!(fake, compositor_subscription)
        @test length(drain_events!(fake)) >= 1
        @test validate_protocol_request(protocol_request("state", "state.get"))["method"] == "state.get"
        @test_throws JuliaShellError validate_protocol_request(protocol_request("bad", "apps.focus"))
        daemon_state = JuliaShell._daemon_dispatch(protocol_request("state", "state.get"), repo, env)
        @test daemon_state["schema"] == PROJECTION_SCHEMA
        @test daemon_state["service"] == "online"
    end
end

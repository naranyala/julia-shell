function _issue_dict(issue::ValidationIssue)
    Dict{String,Any}("path" => issue.path, "field" => issue.field, "value" => issue.value,
                     "expected" => issue.expected, "message" => issue.message)
end

function _pin_dict(pin::Pin)
    result = Dict{String,Any}("desktop_id" => pin.desktop_id, "position" => pin.position,
                              "match_app_ids" => pin.match_app_ids, "launch" => pin.launch)
    pin.label === nothing || (result["label"] = pin.label)
    pin.scope === nothing || (result["scope"] = pin.scope)
    result
end

function _action_dict(action::PlanAction)
    Dict{String,Any}("id" => action.id, "kind" => String(action.kind),
        "source" => action.source, "target" => action.target, "mode" => action.mode,
        "source_hash" => action.source_hash, "target_hash" => action.target_hash,
        "reason" => action.reason)
end

function _plan_dict(current::Plan)
    Dict{String,Any}("id" => current.id, "profile" => current.profile,
        "revision" => current.revision, "hash" => current.hash,
        "actions" => [_action_dict(action) for action in current.actions],
        "conflicts" => current.conflicts, "unsafe" => current.unsafe, "missing" => current.missing)
end

function _transaction_dict(result::TransactionResult)
    Dict{String,Any}("id" => result.id, "operation" => result.operation,
        "phase" => String(result.phase), "revision" => result.revision,
        "snapshot" => result.snapshot === nothing ? nothing : Dict{String,Any}(
            "id" => result.snapshot.id, "path" => result.snapshot.path,
            "status" => result.snapshot.status, "manifest_hash" => result.snapshot.manifest_hash),
        "message" => result.message, "rolled_back" => result.rolled_back,
        "journal" => result.journal)
end

function _parse_cli(args)
    opts = Dict{String,Any}("repo" => get(ENV, "JULIA_SHELL_REPO", "."), "profile" => "personal",
                            "json" => false, "yes" => false, "dry_run" => false, "force" => false)
    positional = String[]
    index = 1
    while index <= length(args)
        arg = String(args[index])
        if arg == "--json"
            opts["json"] = true
        elseif arg == "--yes"
            opts["yes"] = true
        elseif arg == "--dry-run"
            opts["dry_run"] = true
        elseif arg == "--force"
            opts["force"] = true
        elseif arg == "--allow-secret"
            opts["allow_secret"] = true
        elseif startswith(arg, "--")
            key = replace(arg[3:end], "-" => "_")
            index += 1
            index <= length(args) || throw(JuliaShellError(:usage, "option $arg requires a value";
                                                          remediation="run julia-shell --help"))
            opts[key] = args[index]
        else
            push!(positional, arg)
        end
        index += 1
    end
    isempty(positional) && throw(JuliaShellError(:usage, "a command is required"; remediation="run julia-shell --help"))
    positional[1], positional[2:end], opts
end

function _human_plan(current::Plan)
    lines = String["PLAN $(current.id) profile=$(current.profile) revision=$(current.revision) hash=$(current.hash)"]
    for action in current.actions
        label = uppercase(replace(String(action.kind), "_" => "-"))
        push!(lines, "$(label) $(action.target)" * (action.source === nothing ? "" : " <- $(action.source)"))
    end
    isempty(current.conflicts) && isempty(current.unsafe) && isempty(current.missing) ||
        push!(lines, "Result: blocked")
    join(lines, "\n")
end

function _print_result(result, json::Bool)
    if json
        println(_json_encode(result))
    elseif result isa AbstractString
        println(result)
    else
        println(_human_result(result))
    end
end

function _human_result(result)
    result isa AbstractDict && return join([string(key, ": ", value) for key in sort!(String[string(key) for key in keys(result)])], "\n")
    string(result)
end

function _require_yes(opts, command)
    opts["yes"] || throw(JuliaShellError(:confirmation_required, "$command requires --yes";
                                       remediation="review the plan and pass --yes"))
end

function _export_repository(repo, destination; env=ENV)
    destination = abspath(String(destination))
    ispath(destination) && throw(JuliaShellError(:destination_exists, "export destination already exists";
        details=Dict("path" => destination), remediation="choose a new destination"))
    mkpath(destination)
    for name in ("profiles", "files")
        source = joinpath(abspath(String(repo)), name)
        isdir(source) && _copy_entry(source, joinpath(destination, name))
    end
    manifest = Dict{String,Any}("schema" => 1, "created_at" => string(now(UTC)), "files" => Any[])
    for (directory, _, files) in walkdir(destination)
        for file in files
            full = joinpath(directory, file)
            rel = relpath(full, destination)
            rel == "manifest.toml" && continue
            push!(manifest["files"], Dict{String,Any}("path" => rel, "sha256" => sha256_path(full)))
        end
    end
    manifest["manifest_hash"] = _manifest_hash(manifest["files"])
    save_toml_atomic(joinpath(destination, "manifest.toml"), manifest)
    destination
end

function _doctor(repo; env=ENV)
    checks = Dict{String,Any}[]
    profile_path = repository_profile_path(repo, "personal")
    push!(checks, Dict{String,Any}("name" => "profile", "ok" => isfile(profile_path), "path" => profile_path))
    if isfile(profile_path)
        try
            profile = load_profile(profile_path)
            push!(checks, Dict{String,Any}("name" => "schema", "ok" => true, "profile" => profile.name))
            current = plan(profile; repo=repo, env=env)
            push!(checks, Dict{String,Any}("name" => "paths", "ok" => isempty(current.unsafe), "unsafe" => current.unsafe))
            push!(checks, Dict{String,Any}("name" => "sources", "ok" => isempty(current.missing), "missing" => current.missing))
        catch err
            push!(checks, Dict{String,Any}("name" => "schema", "ok" => false, "error" => sprint(showerror, err)))
        end
    end
    journals = _journal_path("_unused"; env)
    journal_dir = dirname(journals)
    stale = String[]
    if isdir(journal_dir)
        for file in readdir(journal_dir)
            endswith(file, ".toml") || continue
            data = _string_dict(TOML.parsefile(joinpath(journal_dir, file)))
            String(get(data, "phase", "")) in ("verified", "rolled_back") || push!(stale, file)
        end
    end
    push!(checks, Dict{String,Any}("name" => "journals", "ok" => isempty(stale), "stale" => stale))
    Dict{String,Any}("ok" => all(Bool(get(check, "ok", false)) for check in checks), "checks" => checks)
end

"CLI entry point. Returns the documented process exit code instead of calling exit itself."
function main(args=ARGS)
    if any(arg -> arg in ("-h", "--help"), args)
        println("julia-shell init|status|plan|apply|adopt|diff|pin|unpin|reorder|snapshot|restore|verify|export|doctor")
        return 0
    end
    command, positional, opts = try
        _parse_cli(args)
    catch err
        println(stderr, _json_encode(Dict("code" => "usage", "message" => sprint(showerror, err))))
        return 2
    end
    repo = String(opts["repo"])
    profile_name = String(opts["profile"])
    json = Bool(opts["json"])
    try
        result = if command == "init"
            init_repository(repo; profile=profile_name, force=Bool(opts["force"]))
            Dict{String,Any}("ok" => true, "repository" => abspath(repo), "profile" => profile_name)
        elseif command == "status"
            status(repo; profile=profile_name)
        elseif command == "plan"
            current = plan(repo; profile=profile_name)
            json ? _plan_dict(current) : _human_plan(current)
        elseif command == "apply"
            current = plan(repo; profile=profile_name)
            if Bool(opts["dry_run"])
                json ? _plan_dict(current) : _human_plan(current)
            else
                _require_yes(opts, "apply")
                _transaction_dict(apply!(current; repo=repo, yes=true, env=ENV,
                                         force=Bool(opts["force"]),
                                         snapshot_root=get(opts, "snapshot_root", nothing)))
            end
        elseif command == "pin"
            _require_yes(opts, "pin")
            isempty(positional) && throw(JuliaShellError(:usage, "pin requires a desktop-file ID"; remediation="run julia-shell pin APP.desktop --yes"))
            pin!(repo, positional[1]; profile=profile_name,
                 position=get(opts, "position", nothing) === nothing ? nothing : parse(Int, String(opts["position"])),
                 expected_revision=get(opts, "revision", nothing) === nothing ? nothing : parse(Int, String(opts["revision"])),
                 request_id=String(get(opts, "request_id", string(uuid4()))))
        elseif command == "unpin"
            _require_yes(opts, "unpin")
            isempty(positional) && throw(JuliaShellError(:usage, "unpin requires a desktop-file ID"; remediation="run julia-shell unpin APP.desktop --yes"))
            unpin!(repo, positional[1]; profile=profile_name,
                   expected_revision=get(opts, "revision", nothing) === nothing ? nothing : parse(Int, String(opts["revision"])),
                   request_id=String(get(opts, "request_id", string(uuid4()))))
        elseif command == "reorder"
            _require_yes(opts, "reorder")
            length(positional) == 2 || throw(JuliaShellError(:usage, "reorder requires FROM and TO"; remediation="run julia-shell reorder 2 1 --yes"))
            reorder!(repo, parse(Int, positional[1]), parse(Int, positional[2]); profile=profile_name,
                     expected_revision=get(opts, "revision", nothing) === nothing ? nothing : parse(Int, String(opts["revision"])),
                     request_id=String(get(opts, "request_id", string(uuid4()))))
        elseif command == "snapshot"
            subcommand = isempty(positional) ? "list" : positional[1]
            if subcommand == "list"
                list_snapshots(; root=get(opts, "snapshot_root", nothing))
            elseif subcommand == "verify"
                isempty(positional) && throw(JuliaShellError(:usage, "snapshot verify requires a path"; remediation="run julia-shell snapshot verify PATH"))
                verify_snapshot(positional[2])
                Dict{String,Any}("ok" => true, "snapshot" => positional[2])
            elseif subcommand == "create"
                current = plan(repo; profile=profile_name)
                _transaction_dict(TransactionResult(string(uuid4()), "snapshot", :verified, current.revision,
                    create_snapshot(current.actions; root=get(opts, "snapshot_root", nothing), profile=profile_name,
                                    plan_hash=current.hash), "snapshot created", false, nothing))
            else
                throw(JuliaShellError(:usage, "unknown snapshot subcommand"; remediation="use create, list, or verify"))
            end
        elseif command == "verify"
            isempty(positional) && throw(JuliaShellError(:usage, "verify requires a snapshot path"; remediation="run julia-shell verify PATH"))
            verify_snapshot(positional[1])
            Dict{String,Any}("ok" => true, "snapshot" => positional[1])
        elseif command == "restore"
            _require_yes(opts, "restore")
            isempty(positional) && throw(JuliaShellError(:usage, "restore requires a snapshot path"; remediation="run julia-shell restore PATH --yes"))
            _transaction_dict(restore_snapshot(positional[1]; ids=positional[2:end], yes=true,
                                                snapshot_root=get(opts, "snapshot_root", nothing), repo=repo))
        elseif command == "export"
            _require_yes(opts, "export")
            destination = isempty(positional) ? repo * ".export" : positional[1]
            Dict{String,Any}("ok" => true, "path" => export_repository(repo, destination))
        elseif command == "doctor"
            _doctor(repo)
        elseif command == "diff"
            current = plan(repo; profile=profile_name)
            selected = isempty(positional) ? current.actions : [a for a in current.actions if a.id == positional[1]]
            json ? Dict{String,Any}("actions" => [_action_dict(a) for a in selected]) : join([String(a.kind) * " " * a.target * ": " * a.reason for a in selected], "\n")
        elseif command == "adopt"
            _require_yes(opts, "adopt")
            isempty(positional) && throw(JuliaShellError(:usage, "adopt requires an existing path";
                remediation="run julia-shell adopt PATH --id NAME --yes"))
            id = String(get(opts, "id", basename(positional[1])))
            adopt!(repo, positional[1]; id=id, target=String(get(opts, "target", positional[1])),
                   profile=profile_name, mode=String(get(opts, "mode", "copy")),
                   allow_secret=Bool(get(opts, "allow_secret", false)),
                   request_id=String(get(opts, "request_id", string(uuid4()))))
        else
            throw(JuliaShellError(:usage, "unknown command: $command"; remediation="run julia-shell --help"))
        end
        _print_result(result, json)
        0
    catch err
        if err isa ValidationError
            error_data = Dict{String,Any}("code" => "validation_error", "message" => sprint(showerror, err),
                "details" => Dict("issues" => [_issue_dict(issue) for issue in err.issues]), "remediation" => "fix the profile and retry")
            code = 2
        elseif err isa JuliaShellError
            error_data = Dict{String,Any}("code" => String(err.code), "message" => err.message,
                "details" => err.details, "remediation" => err.remediation)
            code = err.code == :revision_conflict ? 4 : err.code in (:unsafe_path, :plan_blocked) ? 3 :
                   err.code in (:transaction_failed,) ? 6 : err.code in (:recovery_required,) ? 7 :
                   err.code in (:integrity_failure,) ? 8 : err.code in (:usage, :confirmation_required) ? 2 : 1
        else
            error_data = Dict{String,Any}("code" => "internal_error", "message" => sprint(showerror, err),
                                          "details" => Dict{String,Any}(), "remediation" => "inspect the error and retry")
            code = 1
        end
        println(stderr, _json_encode(error_data))
        code
    end
end

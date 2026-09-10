const DEFAULT_REVISION = 0

function _repository_key(repo::AbstractString)
    bytes = Vector{UInt8}(codeunits(normpath(abspath(String(repo)))))
    _hash_bytes(bytes)[1:16]
end

function _state_file(repo::AbstractString="."; env=ENV)
    joinpath(dockyard_state_dir(; env), "profiles", _repository_key(repo), "state.toml")
end

function _runtime_state(; repo=".", env=ENV)
    file = _state_file(repo; env)
    isfile(file) || return Dict{String,Any}("revision" => DEFAULT_REVISION,
                                            "active_profile" => "personal",
                                            "recent_requests" => Any[])
    data = _string_dict(TOML.parsefile(file))
    get!(data, "revision", DEFAULT_REVISION)
    get!(data, "active_profile", "personal")
    get!(data, "recent_requests", Any[])
    data
end

function _revision(; repo=".", env=ENV)
    value = get(_runtime_state(; repo, env), "revision", DEFAULT_REVISION)
    value isa Integer ? Int(value) : DEFAULT_REVISION
end

function _set_revision!(revision::Integer; repo=".", profile="personal", env=ENV, request_id=nothing, result=nothing)
    state = _runtime_state(; repo, env)
    state["revision"] = Int(revision)
    state["active_profile"] = String(profile)
    if request_id !== nothing
        requests = Any[get(state, "recent_requests", Any[])...]
        push!(requests, Dict{String,Any}("id" => String(request_id), "result" => result === nothing ? Dict{String,Any}() : result))
        length(requests) > 256 && deleteat!(requests, 1:length(requests)-256)
        state["recent_requests"] = requests
    end
    save_toml_atomic(_state_file(repo; env), state)
    state
end

function _idempotent_result(request_id::AbstractString; repo=".", env=ENV)
    for raw in get(_runtime_state(; repo, env), "recent_requests", Any[])
        item = _string_dict(raw)
        String(get(item, "id", "")) == request_id && return get(item, "result", nothing)
    end
    nothing
end

function _path_action(entry::DotfileEntry, repo::String, env)
    source = try
        _safe_source_path(repo, entry.source; env=env)
    catch err
        err isa DockyardError || rethrow()
        return PlanAction(entry.id, :unsafe, nothing, entry.target, entry.mode, nothing, nothing, err.message)
    end
    target = try
        safe_target_path(entry.target; env=env)
    catch err
        err isa DockyardError || rethrow()
        return PlanAction(entry.id, :unsafe, source, entry.target, entry.mode, nothing, nothing, err.message)
    end
    if entry.secret
        return PlanAction(entry.id, :excluded, source, target, entry.mode,
                          _entry_exists(source) ? sha256_path(source) : nothing,
                          _entry_exists(target) ? sha256_path(target) : nothing,
                          "entry is marked secret and is excluded by policy")
    end
    platform = lowercase(string(Sys.KERNEL))
    !isempty(entry.platforms) && !("linux" in lowercase.(entry.platforms) || platform in lowercase.(entry.platforms)) &&
        return PlanAction(entry.id, :excluded, source, target, entry.mode, nothing,
                          _entry_exists(target) ? sha256_path(target) : nothing,
                          "entry is not enabled on this platform")
    !_entry_exists(source) && return PlanAction(entry.id, :missing_source, source, target, entry.mode,
                                                nothing, _entry_exists(target) ? sha256_path(target) : nothing,
                                                "source does not exist")
    source_hash = sha256_path(source)
    target_hash = _entry_exists(target) ? sha256_path(target) : nothing
    !_entry_exists(target) && return PlanAction(entry.id, :create, source, target, entry.mode,
                                               source_hash, nothing, "target does not exist")
    equivalent = if entry.mode == "symlink"
        islink(target) && _resolved_link(target) == normpath(source)
    else
        !islink(target) && target_hash == source_hash
    end
    equivalent && return PlanAction(entry.id, :no_op, source, target, entry.mode,
                                    source_hash, target_hash, "source and target are identical")
    if entry.baseline_hash !== nothing && source_hash != entry.baseline_hash && target_hash != entry.baseline_hash
        return PlanAction(entry.id, :conflict, source, target, entry.mode, source_hash, target_hash,
                          "source and target both changed since the recorded baseline")
    end
    PlanAction(entry.id, :drift, source, target, entry.mode, source_hash, target_hash,
               "target differs from the repository source")
end

function _plan_hash(actions)
    rows = String[]
    for action in actions
        push!(rows, join((action.id, string(action.kind), something(action.source, ""),
                         action.target, something(action.mode, ""),
                         something(action.source_hash, ""), something(action.target_hash, ""),
                         action.reason), "\0"))
    end
    _hash_bytes(Vector{UInt8}(codeunits(join(rows, "\n"))))
end

"Build a deterministic, side-effect-free plan for a validated profile."
function plan(profile::Profile; repo=".", env=ENV, revision=nothing)
    root = abspath(String(repo))
    revision = revision === nothing ? _revision(; repo=root, env=env) : revision
    actions = PlanAction[_path_action(entry, root, env) for entry in profile.dotfiles]
    conflicts = String[a.id for a in actions if a.kind == :conflict]
    unsafe = String[a.id for a in actions if a.kind == :unsafe]
    missing = String[a.id for a in actions if a.kind == :missing_source]
    Plan(string(uuid4()), profile.name, Int(revision), actions, _plan_hash(actions),
         conflicts, unsafe, missing)
end

function plan(repo::AbstractString; profile="personal", env=ENV)
    path = repository_profile_path(repo, profile)
    isfile(path) || throw(DockyardError(:profile_missing, "profile does not exist";
                                        details=Dict("path" => path), remediation="run dockyard init"))
    loaded = load_profile(path)
    plan(loaded; repo=repo, env=env, revision=_revision(; repo=repo, env=env))
end

function _plan_blocked(current_plan::Plan)
    !isempty(current_plan.conflicts) && return "plan contains conflicts: " * join(current_plan.conflicts, ", ")
    !isempty(current_plan.unsafe) && return "plan contains unsafe paths: " * join(current_plan.unsafe, ", ")
    !isempty(current_plan.missing) && return "plan contains missing sources: " * join(current_plan.missing, ", ")
    nothing
end

function _plan_has_changed(action::PlanAction)
    current_source = action.source === nothing || !_entry_exists(action.source) ? nothing : sha256_path(action.source)
    current_target = _entry_exists(action.target) ? sha256_path(action.target) : nothing
    current_source != action.source_hash || current_target != action.target_hash
end

function _journal_path(id::AbstractString; env=ENV)
    joinpath(dockyard_state_dir(; env), "journal", String(id) * ".toml")
end

function _write_journal(path, data)
    data["updated_at"] = string(now(UTC))
    save_toml_atomic(path, data)
end

function _stage_action(action::PlanAction, stage::String)
    action.source === nothing && throw(ArgumentError("action has no source"))
    action.mode == "generated" && throw(DockyardError(:unsupported_mode,
        "generated entries require an explicit renderer and are not enabled yet";
        details=Dict("id" => action.id), remediation="use mode=copy or mode=symlink"))
    action.mode == "symlink" ? symlink(action.source, stage) : _copy_entry(action.source, stage)
    stage
end

function _target_matches(action::PlanAction)
    _entry_exists(action.target) || return false
    action.mode == "symlink" && return islink(action.target) &&
        _resolved_link(action.target) == normpath(String(action.source))
    !islink(action.target) && sha256_path(action.target) == action.source_hash
end

function _rollback_steps!(steps)
    for raw in reverse(steps)
        step = _string_dict(raw)
        status = String(get(step, "status", "staged"))
        target = String(step["target"])
        backup = String(step["backup"])
        stage = String(step["stage"])
        status in ("committed", "target_moved") || begin
            _entry_exists(stage) && _remove_entry(stage)
            continue
        end
        _entry_exists(target) && _remove_entry(target)
        _entry_exists(backup) && (mkpath(dirname(target)); mv(backup, target; force=false))
        _entry_exists(stage) && _remove_entry(stage)
    end
end

"Apply a plan through snapshot, stage, commit, and verification phases."
function apply!(current_plan::Plan; repo=".", env=ENV, yes=false, force=false,
                snapshot_root=nothing)
    blocked = _plan_blocked(current_plan)
    blocked !== nothing && throw(DockyardError(:plan_blocked, blocked;
        details=Dict("conflicts" => current_plan.conflicts, "unsafe" => current_plan.unsafe,
                     "missing" => current_plan.missing), remediation="inspect the plan and run diff before applying"))
    yes || throw(DockyardError(:confirmation_required, "apply requires explicit confirmation";
                               details=Dict("plan_hash" => current_plan.hash),
                               remediation="review the plan, then pass --yes"))
    actions = PlanAction[a for a in current_plan.actions if a.kind in (:create, :drift, :replace)]
    !force && any(_plan_has_changed, actions) && throw(DockyardError(:plan_stale,
        "the filesystem changed after the plan was created";
        details=Dict("plan_hash" => current_plan.hash),
        remediation="run plan again and review the new changes"))
    isempty(actions) && return TransactionResult(string(uuid4()), "apply", :verified,
                                                  current_plan.revision, nothing, "nothing to do", false, nothing)
    root = abspath(String(repo))
    transaction_id = string(uuid4())
    journal_path = _journal_path(transaction_id; env)
    journal = Dict{String,Any}("schema" => 1, "id" => transaction_id, "operation" => "apply",
        "profile" => current_plan.profile, "plan_hash" => current_plan.hash,
        "phase" => "planned", "steps" => Any[], "created_at" => string(now(UTC)))
    _write_journal(journal_path, journal)
    snapshot = nothing
    steps = Any[]
    try
        snapshot = create_snapshot(actions; root=snapshot_root, operation="apply",
                                   profile=current_plan.profile, plan_hash=current_plan.hash,
                                   revision=current_plan.revision, env=env)
        journal["phase"] = "snapshotted"
        journal["snapshot"] = snapshot.path
        _write_journal(journal_path, journal)
        journal["phase"] = "staged"
        for action in actions
            mkpath(dirname(action.target))
            stage = action.target * ".dockyard-stage-" * transaction_id * "-" * action.id
            backup = action.target * ".dockyard-backup-" * transaction_id * "-" * action.id
            _entry_exists(stage) && _remove_entry(stage)
            _entry_exists(backup) && _remove_entry(backup)
            step = Dict{String,Any}("id" => action.id, "target" => action.target,
                                    "stage" => stage, "backup" => backup,
                                    "had_target" => _entry_exists(action.target), "status" => "staging")
            push!(steps, step)
            journal["steps"] = steps
            _write_journal(journal_path, journal)
            _stage_action(action, stage)
            step["status"] = "staged"
            journal["steps"] = steps
            _write_journal(journal_path, journal)
        end
        journal["phase"] = "committed"
        _write_journal(journal_path, journal)
        for step in steps
            target = String(step["target"])
            backup = String(step["backup"])
            stage = String(step["stage"])
            if Bool(step["had_target"])
                mv(target, backup; force=false)
                step["status"] = "target_moved"
                journal["steps"] = steps
                _write_journal(journal_path, journal)
            end
            mv(stage, target; force=false)
            step["status"] = "committed"
            journal["steps"] = steps
            _write_journal(journal_path, journal)
        end
        for action in actions
            _target_matches(action) || throw(DockyardError(:verification_failed,
                "committed target failed verification"; details=Dict("id" => action.id, "target" => action.target),
                remediation="restore the pre-change snapshot"))
        end
        for step in steps
            _entry_exists(String(step["backup"])) && _remove_entry(String(step["backup"]))
        end
        journal["phase"] = "verified"
        _write_journal(journal_path, journal)
        _update_baselines(root, current_plan, env)
        TransactionResult(transaction_id, "apply", :verified, current_plan.revision,
                          snapshot, "applied successfully", false, journal_path)
    catch err
        try
            _rollback_steps!(steps)
            journal["phase"] = "rolled_back"
            journal["error"] = sprint(showerror, err)
            journal["steps"] = steps
            _write_journal(journal_path, journal)
        catch rollback_error
            journal["phase"] = "failed"
            journal["error"] = sprint(showerror, err)
            journal["rollback_error"] = sprint(showerror, rollback_error)
            _write_journal(journal_path, journal)
            throw(DockyardError(:recovery_required, "transaction failed and rollback needs recovery";
                details=Dict("journal" => journal_path, "error" => sprint(showerror, err),
                             "rollback_error" => sprint(showerror, rollback_error)),
                remediation="keep the journal and run dockyard doctor"))
        end
        err isa DockyardError && throw(err)
        throw(DockyardError(:transaction_failed, "transaction failed and was rolled back";
            details=Dict("journal" => journal_path, "error" => sprint(showerror, err)),
            remediation="inspect the journal and retry after resolving the reported error"))
    end
end

"Recover unfinished transactions recorded by the journal before serving clients."
function recover_journals!(; env=ENV)
    directory = joinpath(dockyard_state_dir(; env), "journal")
    isdir(directory) || return Dict{String,Any}("recovered" => String[], "failed" => String[])
    recovered = String[]
    failed = String[]
    for name in readdir(directory)
        endswith(name, ".toml") || continue
        path = joinpath(directory, name)
        data = try
            _string_dict(TOML.parsefile(path))
        catch
            push!(failed, path)
            continue
        end
        phase = String(get(data, "phase", ""))
        phase in ("verified", "rolled_back", "failed") && continue
        try
            _rollback_steps!(get(data, "steps", Any[]))
            data["phase"] = "rolled_back"
            data["recovered_at"] = string(now(UTC))
            _write_journal(path, data)
            push!(recovered, path)
        catch
            push!(failed, path)
        end
    end
    Dict{String,Any}("recovered" => recovered, "failed" => failed)
end

function _update_baselines(repo::String, current_plan::Plan, env)
    profile_path = repository_profile_path(repo, current_plan.profile)
    isfile(profile_path) || return
    profile = load_profile(profile_path)
    by_id = Dict{String,PlanAction}(action.id => action for action in current_plan.actions)
    entries = DotfileEntry[]
    for entry in profile.dotfiles
        action = get(by_id, entry.id, nothing)
        if action !== nothing && action.source_hash !== nothing && action.kind in (:create, :drift, :replace)
            push!(entries, DotfileEntry(entry.id, entry.source, entry.target; mode=entry.mode,
                                        platforms=entry.platforms, secret=entry.secret,
                                        baseline_hash=action.source_hash))
        else
            push!(entries, entry)
        end
    end
    save_profile(profile_path, Profile(profile.name; schema=profile.schema,
                                       dock=profile.dock, dotfiles=entries))
end

function _mutate_profile(transform, repo::AbstractString, profile_name::AbstractString, request_id;
                         expected_revision=nothing, env=ENV, operation)
    existing = _idempotent_result(request_id; repo=repo, env)
    existing !== nothing && return existing
    profile_path = repository_profile_path(repo, profile_name)
    profile = load_profile(profile_path)
    current_revision = _revision(; repo=repo, env)
    expected_revision !== nothing && Int(expected_revision) != current_revision &&
        throw(DockyardError(:revision_conflict, "profile revision is stale";
            details=Dict("expected_revision" => Int(expected_revision), "current_revision" => current_revision),
            remediation="refetch status and retry with the current revision"))
    updated = transform(profile)
    save_profile(profile_path, updated)
    new_revision = current_revision + 1
    result = Dict{String,Any}("ok" => true, "operation" => String(operation),
                              "revision" => new_revision, "request_id" => String(request_id))
    _set_revision!(new_revision; repo=repo, profile=profile_name, env=env, request_id=request_id, result=result)
    result
end

function _renumber(pins)
    [Pin(pin.desktop_id; position=index * 10, match_app_ids=pin.match_app_ids,
         launch=pin.launch, label=pin.label, scope=pin.scope) for (index, pin) in enumerate(pins)]
end

function pin!(repo::AbstractString, desktop_id::AbstractString; profile="personal", position=nothing,
              expected_revision=nothing, request_id=string(uuid4()), env=ENV,
              match_app_ids=String[], label=nothing)
    _mutate_profile(repo, profile, request_id; expected_revision, env, operation="pin") do current
        any(pin.desktop_id == desktop_id for pin in current.dock.pins) &&
            throw(DockyardError(:duplicate_pin, "application is already pinned";
                                details=Dict("desktop_id" => String(desktop_id)), remediation="use reorder or unpin"))
        pins = ordered_pins(current.dock)
        index = position === nothing ? length(pins) + 1 : clamp(Int(position), 1, length(pins) + 1)
        insert!(pins, index, Pin(desktop_id; position=index * 10,
                                 match_app_ids=match_app_ids, label=label))
        Profile(current.name; schema=current.schema,
                dock=Dock(; edge=current.dock.edge, output=current.dock.output,
                           autohide=current.dock.autohide, pins=_renumber(pins)),
                dotfiles=current.dotfiles)
    end
end

function unpin!(repo::AbstractString, desktop_id::AbstractString; profile="personal",
                expected_revision=nothing, request_id=string(uuid4()), env=ENV)
    _mutate_profile(repo, profile, request_id; expected_revision, env, operation="unpin") do current
        pins = ordered_pins(current.dock)
        index = findfirst(pin -> pin.desktop_id == desktop_id, pins)
        index === nothing && throw(DockyardError(:pin_missing, "application is not pinned";
            details=Dict("desktop_id" => String(desktop_id)), remediation="inspect dockyard status"))
        deleteat!(pins, index)
        Profile(current.name; schema=current.schema,
                dock=Dock(; edge=current.dock.edge, output=current.dock.output,
                           autohide=current.dock.autohide, pins=_renumber(pins)),
                dotfiles=current.dotfiles)
    end
end

function reorder!(repo::AbstractString, from::Integer, to::Integer; profile="personal",
                  expected_revision=nothing, request_id=string(uuid4()), env=ENV)
    _mutate_profile(repo, profile, request_id; expected_revision, env, operation="reorder") do current
        pins = ordered_pins(current.dock)
        (1 <= from <= length(pins) && 1 <= to <= length(pins)) ||
            throw(DockyardError(:invalid_position, "reorder position is outside the pin list";
                                details=Dict("from" => from, "to" => to, "count" => length(pins)),
                                remediation="use positions within the current pin list"))
        item = splice!(pins, from)
        insert!(pins, to, item)
        Profile(current.name; schema=current.schema,
                dock=Dock(; edge=current.dock.edge, output=current.dock.output,
                           autohide=current.dock.autohide, pins=_renumber(pins)),
                dotfiles=current.dotfiles)
    end
end

function _likely_secret(path::AbstractString)
    lowercase(basename(String(path))) in (".env", ".netrc", "credentials", "secrets", "secret") ||
        occursin(r"(token|password|passwd|private[_-]?key|id_rsa)", lowercase(String(path)))
end

"Import an existing user path into the portable file tree after a safety snapshot."
function adopt!(repo::AbstractString, existing::AbstractString; id=basename(existing), target=existing,
                profile="personal", mode="copy", allow_secret=false, env=ENV,
                expected_revision=nothing, request_id=string(uuid4()), snapshot_root=nothing)
    source_path = abspath(String(existing))
    _entry_exists(source_path) || throw(DockyardError(:source_missing, "adopt source does not exist";
        details=Dict("path" => source_path), remediation="choose an existing file or directory"))
    _likely_secret(source_path) && !allow_secret &&
        throw(DockyardError(:secret_excluded, "likely secret paths are excluded by default";
            details=Dict("path" => source_path), remediation="use a secret manager or explicitly pass --allow-secret"))
    mode in ("copy", "symlink") || throw(DockyardError(:invalid_mode, "adopt mode must be copy or symlink";
        remediation="use --mode copy or --mode symlink"))
    target_path = safe_target_path(target; env=env)
    repository = abspath(String(repo))
    destination = normpath(joinpath(repository, "files", String(id)))
    is_path_within(destination, repository) || throw(DockyardError(:unsafe_path, "adopt id escapes the repository";
        remediation="use a simple logical ID"))
    is_path_within(source_path, destination) && throw(DockyardError(:invalid_adoption, "adopt source is already below the destination";
        remediation="choose a source outside the repository file tree"))
    profile_path = repository_profile_path(repository, profile)
    current = load_profile(profile_path)
    any(entry.id == id for entry in current.dotfiles) && throw(DockyardError(:duplicate_entry, "dotfile id is already managed";
        details=Dict("id" => String(id)), remediation="choose another id or edit the existing entry"))
    snapshot = create_snapshot([PlanAction(String(id), :replace, source_path, target_path, mode,
                                            sha256_path(source_path), sha256_path(target_path), "pre-adopt")];
                               root=snapshot_root, operation="adopt", profile=profile, env=env)
    ispath(destination) && throw(DockyardError(:destination_exists, "repository destination already exists";
        details=Dict("path" => destination), remediation="choose another logical ID"))
    mode == "symlink" ? (mkpath(dirname(destination)); symlink(source_path, destination)) : _copy_entry(source_path, destination)
    result = _mutate_profile(repository, profile, request_id; expected_revision, env, operation="adopt") do loaded
        entry = DotfileEntry(String(id), relpath(destination, repository), String(target); mode=mode,
                             secret=allow_secret, baseline_hash=sha256_path(source_path))
        Profile(loaded.name; schema=loaded.schema, dock=loaded.dock,
                dotfiles=vcat(loaded.dotfiles, [entry]))
    end
    result["snapshot"] = snapshot.id
    result
end

function status(repo::AbstractString="."; profile="personal", env=ENV)
    profile_path = repository_profile_path(repo, profile)
    state = _runtime_state(; repo=repo, env=env)
    result = Dict{String,Any}("service" => "offline", "version" => "0.1.0",
        "profile" => String(profile), "revision" => Int(get(state, "revision", 0)),
        "compositor" => haskey(env, "HYPRLAND_INSTANCE_SIGNATURE") ? "hyprland" : "unknown",
        "last_transaction" => nothing, "profile_path" => profile_path)
    if isfile(profile_path)
        loaded = try
            load_profile(profile_path)
        catch err
            result["health"] = "invalid"
            result["error"] = sprint(showerror, err)
            return result
        end
        current_plan = plan(loaded; repo=repo, env=env, revision=result["revision"])
        result["health"] = isempty(current_plan.conflicts) && isempty(current_plan.unsafe) ? "ready" : "degraded"
        result["pins"] = length(loaded.dock.pins)
        result["dotfiles"] = length(loaded.dotfiles)
        result["drift"] = Dict{String,Any}("create" => count(x -> x.kind == :create, current_plan.actions),
                                            "drift" => count(x -> x.kind == :drift, current_plan.actions),
                                            "conflict" => length(current_plan.conflicts),
                                            "missing" => length(current_plan.missing))
    else
        result["health"] = "uninitialized"
    end
    result
end

function restore_snapshot(path::AbstractString; ids=String[], yes=false, env=ENV, snapshot_root=nothing)
    yes || throw(DockyardError(:confirmation_required, "restore requires explicit confirmation";
                               details=Dict("snapshot" => String(path)), remediation="review the snapshot and pass --yes"))
    verify_snapshot(path)
    data, directory = _load_snapshot(path)
    entries = [_string_dict(raw) for raw in get(data, "entries", Any[])]
    selected = isempty(ids) ? entries : begin
        wanted = Set(String[string(id) for id in ids])
        unknown = setdiff(wanted, Set(String[String(entry["id"]) for entry in entries]))
        isempty(unknown) || throw(DockyardError(:entry_missing, "snapshot selector does not match an entry";
            details=Dict("ids" => collect(unknown)), remediation="use snapshot list or omit selectors"))
        [entry for entry in entries if String(entry["id"]) in wanted]
    end
    actions = PlanAction[]
    for entry in selected
        target = safe_target_path(String(entry["target"]); env=env)
        payload = joinpath(directory, String(entry["relative"]))
        push!(actions, PlanAction(String(entry["id"]), :replace, payload, target,
                                  String(entry["type"]) == "symlink" ? "symlink" : "copy",
                                  String(entry["sha256"]), sha256_path(target), "snapshot restore"))
    end
    pre = create_snapshot(actions; root=snapshot_root, operation="restore", reason="pre-restore", env)
    transaction_id = string(uuid4())
    journal_path = _journal_path(transaction_id; env)
    steps = Any[]
    journal = Dict{String,Any}("schema" => 1, "id" => transaction_id, "operation" => "restore",
        "phase" => "staged", "snapshot" => directory, "steps" => steps)
    _write_journal(journal_path, journal)
    try
        for action in actions
            mkpath(dirname(action.target))
            stage = action.target * ".dockyard-stage-" * transaction_id * "-" * action.id
            backup = action.target * ".dockyard-backup-" * transaction_id * "-" * action.id
            _entry_exists(stage) && _remove_entry(stage)
            _entry_exists(backup) && _remove_entry(backup)
            step = Dict{String,Any}("id" => action.id, "target" => action.target,
                                    "stage" => stage, "backup" => backup,
                                    "had_target" => _entry_exists(action.target), "status" => "staging")
            push!(steps, step)
            journal["steps"] = steps
            _write_journal(journal_path, journal)
            if action.mode == "symlink"
                symlink(String(get(selected[findfirst(x -> String(x["id"]) == action.id, selected)], "link_target", "")), stage)
            else
                _copy_entry(String(action.source), stage)
            end
            step["status"] = "staged"
            journal["steps"] = steps
            _write_journal(journal_path, journal)
        end
        journal["phase"] = "committed"
        _write_journal(journal_path, journal)
        for step in steps
            Bool(step["had_target"]) && mv(String(step["target"]), String(step["backup"]); force=false)
            step["status"] = "target_moved"
            _write_journal(journal_path, journal)
            mv(String(step["stage"]), String(step["target"]); force=false)
            step["status"] = "committed"
            _write_journal(journal_path, journal)
        end
        for step in steps
            _entry_exists(String(step["backup"])) && _remove_entry(String(step["backup"]))
        end
        journal["phase"] = "verified"
        _write_journal(journal_path, journal)
        TransactionResult(transaction_id, "restore", :verified, _revision(; env=env), pre,
                          "restored successfully", false, journal_path)
    catch err
        try
            _rollback_steps!(steps)
            journal["phase"] = "rolled_back"
            journal["error"] = sprint(showerror, err)
            _write_journal(journal_path, journal)
        catch rollback_error
            throw(DockyardError(:recovery_required, "restore failed and rollback needs recovery";
                details=Dict("journal" => journal_path, "error" => sprint(showerror, err),
                             "rollback_error" => sprint(showerror, rollback_error)),
                remediation="run doctor with the journal path"))
        end
        err isa DockyardError && throw(err)
        throw(DockyardError(:transaction_failed, "restore failed and was rolled back";
            details=Dict("journal" => journal_path), remediation="inspect the journal and retry"))
    end
end

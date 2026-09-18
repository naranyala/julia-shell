function _daemon_compositor(env)
    haskey(env, "HYPRLAND_INSTANCE_SIGNATURE") || return nothing
    HyprlandCompositor(; env=env, eager=false)
end

function _launch_receipt_dict(receipt::LaunchReceipt)
    Dict{String,Any}("id" => receipt.id, "argv" => receipt.argv,
                     "accepted" => receipt.accepted, "pid" => receipt.pid,
                     "message" => receipt.message)
end

function _daemon_dispatch(request, repo::String, env)
    method = String(get(request, "method", ""))
    params = _string_dict(get(request, "params", Dict{String,Any}()))
    profile = String(get(params, "profile", "personal"))
    if method == "status"
        result = status(repo; profile, env=env)
        result["service"] = "online"
        return result
    elseif method == "plan"
        current = plan(repo; profile, env=env)
        return _plan_dict(current)
    elseif method == "state.get"
        return state_projection(repo; profile, env, compositor=_daemon_compositor(env))
    elseif method == "pins.pin"
        return pin!(repo, String(params["desktop_id"]);
            profile,
            position=get(params, "position", nothing),
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    elseif method == "pins.unpin"
        return unpin!(repo, String(params["desktop_id"]);
            profile,
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    elseif method == "pins.reorder"
        return reorder!(repo, Int(params["from"]), Int(params["to"]);
            profile,
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    elseif method in ("apps.focus", "apps.close")
        compositor = _daemon_compositor(env)
        method == "apps.focus" ? focus_toplevel!(compositor, String(params["window_id"])) :
            close_toplevel!(compositor, String(params["window_id"]))
        Dict{String,Any}("ok" => true, "operation" => method,
                         "window_id" => String(params["window_id"]))
    elseif method == "apps.launch"
        entries = discover_applications(; env)
        requested = String(params["desktop_id"])
        entry = get(entries, requested, nothing)
        entry === nothing && begin
            resolved = resolve_application(requested; entries)
            selected = get(resolved, "desktop_id", nothing)
            selected === nothing && throw(JuliaShellError(:application_missing, "application desktop entry was not found";
                details=Dict("desktop_id" => requested), remediation="install the application or repair the pin"))
            entry = get(entries, String(selected), nothing)
        end
        entry === nothing && throw(JuliaShellError(:application_missing, "application desktop entry was not found";
            details=Dict("desktop_id" => requested), remediation="install the application or repair the pin"))
        argv = launch_arguments(entry)
        isempty(argv) && throw(JuliaShellError(:invalid_launch, "application has no executable command";
            details=Dict("desktop_id" => requested), remediation="repair the desktop entry"))
        receipt = launch_application!(_daemon_compositor(env), argv)
        _launch_receipt_dict(receipt)
    else
        throw(JuliaShellError(:unknown_method, "unknown protocol method";
                            details=Dict("method" => method), remediation="use state.get, status, plan, pins, or apps methods"))
    end
end

function _serve_client(client, repo, env)
    try
        for line in eachline(client)
            isempty(strip(line)) && continue
            request_id = ""
            try
                request = decode_message(line)
                validate_protocol_request(request)
                request_id = String(get(request, "id", ""))
                result = _daemon_dispatch(request, repo, env)
                write(client, encode_message(protocol_response(request_id, result)))
                method = String(get(request, "method", ""))
                if startswith(method, "pins.")
                    revision = result isa AbstractDict ? Int(get(result, "revision", _revision(; repo, env))) :
                               _revision(; repo, env)
                    write(client, encode_message(protocol_event("state.changed", revision, ["pins", "dock"])))
                end
            catch err
                error_data = if err isa JuliaShellError
                    Dict{String,Any}("code" => String(err.code), "message" => err.message,
                                     "details" => err.details, "remediation" => err.remediation)
                elseif err isa ValidationError
                    Dict{String,Any}("code" => "validation_error", "message" => sprint(showerror, err),
                                     "details" => Dict("issues" => [_issue_dict(issue) for issue in err.issues]),
                                     "remediation" => "fix the profile and retry")
                else
                    Dict{String,Any}("code" => "internal_error", "message" => sprint(showerror, err),
                                     "details" => Dict{String,Any}(), "remediation" => "inspect daemon logs")
                end
                write(client, encode_message(protocol_error(request_id, error_data)))
            end
            flush(client)
        end
    finally
        close(client)
    end
end

"Run the resident Unix-domain-socket service. This function blocks until interrupted."
function run_daemon(repo::AbstractString="."; socket_path=nothing, env=ENV)
    path = socket_path === nothing ? joinpath(juliashell_runtime_dir(; env), "julia-shell.sock") : abspath(String(socket_path))
    ncodeunits(path) <= 100 || throw(JuliaShellError(:socket_path_too_long, "Unix socket path is too long";
        details=Dict("path" => path, "bytes" => ncodeunits(path)), remediation="set XDG_RUNTIME_DIR to a shorter path"))
    mkpath(dirname(path))
    chmod(dirname(path), 0o700)
    recover_journals!(; env=env)
    ispath(path) && rm(path; force=true)
    server = listen(path)
    chmod(path, 0o600)
    watchdog_timer = nothing
    try
        notify_ready!(status="julia-shell daemon listening on $path")
        interval = watchdog_interval_seconds(; env)
        if interval !== nothing
            watchdog_timer = Timer(interval; interval) do _
                try
                    notify_watchdog!()
                catch
                    # A persistent notification failure will still be exposed
                    # by systemd's watchdog timeout and the service journal.
                end
            end
        end
        while true
            client = accept(server)
            @async _serve_client(client, abspath(String(repo)), env)
        end
    finally
        watchdog_timer === nothing || close(watchdog_timer)
        notify_stopping!()
        close(server)
        ispath(path) && rm(path; force=true)
    end
end

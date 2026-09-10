function _daemon_dispatch(request, repo::String, env)
    method = String(get(request, "method", ""))
    params = _string_dict(get(request, "params", Dict{String,Any}()))
    if method == "status"
        return status(repo; profile=String(get(params, "profile", "personal")), env=env)
    elseif method == "plan"
        current = plan(repo; profile=String(get(params, "profile", "personal")), env=env)
        return _plan_dict(current)
    elseif method == "pins.pin"
        return pin!(repo, String(params["desktop_id"]);
            profile=String(get(params, "profile", "personal")),
            position=get(params, "position", nothing),
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    elseif method == "pins.unpin"
        return unpin!(repo, String(params["desktop_id"]);
            profile=String(get(params, "profile", "personal")),
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    elseif method == "pins.reorder"
        return reorder!(repo, Int(params["from"]), Int(params["to"]);
            profile=String(get(params, "profile", "personal")),
            expected_revision=get(params, "if_revision", nothing),
            request_id=String(get(request, "id", string(uuid4()))), env=env)
    else
        throw(DockyardError(:unknown_method, "unknown protocol method";
                            details=Dict("method" => method), remediation="use status, plan, or pins methods"))
    end
end

function _serve_client(client, repo, env)
    try
        for line in eachline(client)
            isempty(strip(line)) && continue
            request_id = ""
            try
                request = decode_message(line)
                request_id = String(get(request, "id", ""))
                result = _daemon_dispatch(request, repo, env)
                write(client, encode_message(protocol_response(request_id, result)))
            catch err
                error_data = if err isa DockyardError
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
    path = socket_path === nothing ? joinpath(dockyard_runtime_dir(; env), "dockyard.sock") : abspath(String(socket_path))
    ncodeunits(path) <= 100 || throw(DockyardError(:socket_path_too_long, "Unix socket path is too long";
        details=Dict("path" => path, "bytes" => ncodeunits(path)), remediation="set XDG_RUNTIME_DIR to a shorter path"))
    mkpath(dirname(path))
    chmod(dirname(path), 0o700)
    recover_journals!(; env=env)
    ispath(path) && rm(path; force=true)
    server = listen(path)
    chmod(path, 0o600)
    try
        while true
            client = accept(server)
            @async _serve_client(client, abspath(String(repo)), env)
        end
    finally
        close(server)
        ispath(path) && rm(path; force=true)
    end
end

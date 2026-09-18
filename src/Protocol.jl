"""
Protocol — julia-shelld daemon protocol validation and client.

This module provides domain-specific request validation, protocol envelope
constructors, and the daemon socket client.  The pure JSON codec and JSONL
framing live in `JSONLProtocol.jl`.

This module depends on `JSONLProtocol.jl` for `decode_json`, `json_encode`,
`encode_message`, `decode_message`, and `PROTOCOL_VERSION`.  It also depends
on `JuliaShellError` for structured error reporting.
"""

function _invalid_request(message; field=nothing, value=nothing)
    details = Dict{String,Any}()
    field === nothing || (details["field"] = String(field))
    value === nothing || (details["value"] = value)
    JuliaShellError(:invalid_request, String(message); details,
                    remediation="send a valid v$(PROTOCOL_VERSION) daemon request")
end

"""
    decode_message(line; max_bytes=1024*1024) -> Dict{String,Any}

Decode one JSONL line and validate the protocol version.  Wraps
`jsonl_decode` with version checking.
"""
function decode_message(line::AbstractString; max_bytes=1024 * 1024)
    value = try
        jsonl_decode(line; max_bytes)
    catch err
        err isa CodecError && throw(JuliaShellError(err.code, err.message;
            details=err.details === nothing ? Dict{String,Any}() : err.details,
            remediation=err.remediation))
        rethrow()
    end
    version = get(value, "v", nothing)
    version isa Integer && !(version isa Bool) && version == PROTOCOL_VERSION ||
        throw(JuliaShellError(:protocol_version, "unsupported protocol version";
        details=Dict("received" => version, "supported" => PROTOCOL_VERSION),
        remediation="upgrade the client or daemon"))
    value
end

"""
    encode_message(message::AbstractDict) -> String

Encode a dict to a versioned JSONL envelope.  Wraps `jsonl_encode`.
"""
encode_message(message::AbstractDict) = jsonl_encode(message)

"""
    validate_protocol_request(request::AbstractDict) -> AbstractDict

Validate a daemon request envelope.  Checks protocol version, required fields
(id, method, params), and method-specific parameter constraints.
"""
function validate_protocol_request(request::AbstractDict)
    version = get(request, "v", nothing)
    version isa Integer && !(version isa Bool) && version == PROTOCOL_VERSION ||
        throw(_invalid_request("request has an unsupported protocol version"; field="v",
                               value=version))
    id = get(request, "id", nothing)
    id isa AbstractString && !isempty(strip(String(id))) ||
        throw(_invalid_request("request id must be a non-empty string"; field="id", value=id))
    method = get(request, "method", nothing)
    method isa AbstractString && !isempty(strip(String(method))) ||
        throw(_invalid_request("request method must be a non-empty string"; field="method", value=method))
    params = get(request, "params", Dict{String,Any}())
    params isa AbstractDict ||
        throw(_invalid_request("request params must be an object"; field="params", value=params))

    profile = get(params, "profile", nothing)
    profile === nothing || (profile isa AbstractString && !isempty(strip(String(profile))) ||
        throw(_invalid_request("profile must be a non-empty string"; field="params.profile", value=profile)))
    if method in ("pins.pin", "pins.unpin", "apps.launch")
        desktop_id = get(params, "desktop_id", nothing)
        desktop_id isa AbstractString && !isempty(strip(String(desktop_id))) ||
            throw(_invalid_request("desktop_id must be a non-empty string"; field="params.desktop_id", value=desktop_id))
    elseif method in ("apps.focus", "apps.close")
        window_id = get(params, "window_id", nothing)
        window_id isa AbstractString && !isempty(strip(String(window_id))) ||
            throw(_invalid_request("window_id must be a non-empty string"; field="params.window_id", value=window_id))
    elseif method == "pins.reorder"
        for field in ("from", "to")
            value = get(params, field, nothing)
            value isa Integer && !(value isa Bool) && value > 0 ||
                throw(_invalid_request("reorder positions must be positive integers"; field="params.$field", value=value))
        end
    end
    if haskey(params, "if_revision")
        revision = params["if_revision"]
        revision isa Integer && !(revision isa Bool) && revision >= 0 ||
            throw(_invalid_request("if_revision must be a non-negative integer"; field="params.if_revision", value=revision))
    end
    if haskey(params, "position")
        position = params["position"]
        position isa Integer && !(position isa Bool) && position > 0 ||
            throw(_invalid_request("position must be a positive integer"; field="params.position", value=position))
    end
    request
end

"""
    protocol_request(id, method, params=Dict{String,Any}()) -> Dict{String,Any}

Construct a versioned daemon request envelope.
"""
protocol_request(id, method, params=Dict{String,Any}()) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "method" => String(method), "params" => params)

"""
    protocol_response(id, result) -> Dict{String,Any}

Construct a versioned daemon success response envelope.
"""
protocol_response(id, result) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "ok" => true, "result" => result)

"""
    protocol_error(id, error) -> Dict{String,Any}

Construct a versioned daemon error response envelope.
"""
protocol_error(id, error) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "ok" => false, "error" => error)

"""
    protocol_event(event, revision, topics) -> Dict{String,Any}

Construct a versioned daemon server-push event envelope.
"""
protocol_event(event, revision, topics) = Dict{String,Any}("v" => PROTOCOL_VERSION, "event" => String(event), "revision" => Int(revision), "topics" => topics)

"""
    request_daemon(socket_path, message) -> Dict{String,Any}

Perform one request/response round trip over the per-user Unix socket.
Validates the request, connects, writes, reads, and decodes the response.
"""
function request_daemon(socket_path::AbstractString, message::AbstractDict)
    validate_protocol_request(message)
    socket = try
        connect(String(socket_path))
    catch err
        throw(JuliaShellError(:daemon_unavailable, "could not connect to julia-shelld";
            details=Dict("socket" => String(socket_path), "error" => sprint(showerror, err)),
            remediation="start julia-shelld or use the offline CLI"))
    end
    try
        write(socket, encode_message(message))
        flush(socket)
        decode_message(readline(socket))
    finally
        close(socket)
    end
end

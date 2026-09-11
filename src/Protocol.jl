mutable struct _JSONParser
    text::Vector{Char}
    index::Int
end

const PROTOCOL_VERSION = 1

_json_skip!(p) = while p.index <= length(p.text) && p.text[p.index] in (' ', '\n', '\r', '\t'); p.index += 1; end

function _json_string!(p)
    p.text[p.index] == '"' || throw(ArgumentError("expected JSON string"))
    p.index += 1
    result = IOBuffer()
    while p.index <= length(p.text)
        character = p.text[p.index]
        p.index += 1
        character == '"' && return String(take!(result))
        character != '\\' && (write(result, character); continue)
        p.index > length(p.text) && throw(ArgumentError("unterminated JSON escape"))
        escaped = p.text[p.index]
        p.index += 1
        escaped == '"' && write(result, '"')
        escaped == '\\' && write(result, '\\')
        escaped == '/' && write(result, '/')
        escaped == 'b' && write(result, '\b')
        escaped == 'f' && write(result, '\f')
        escaped == 'n' && write(result, '\n')
        escaped == 'r' && write(result, '\r')
        escaped == 't' && write(result, '\t')
        if escaped == 'u'
            p.index + 3 <= length(p.text) || throw(ArgumentError("short unicode escape"))
            code = parse(Int, String(p.text[p.index:p.index+3]); base=16)
            write(result, Char(code))
            p.index += 4
        elseif !(escaped in ('"', '\\', '/', 'b', 'f', 'n', 'r', 't'))
            throw(ArgumentError("invalid JSON escape"))
        end
    end
    throw(ArgumentError("unterminated JSON string"))
end

function _json_value!(p)
    _json_skip!(p)
    p.index <= length(p.text) || throw(ArgumentError("unexpected end of JSON"))
    character = p.text[p.index]
    character == '"' && return _json_string!(p)
    if character == '{'
        p.index += 1
        result = Dict{String,Any}()
        _json_skip!(p)
        p.index <= length(p.text) && p.text[p.index] == '}' && (p.index += 1; return result)
        while true
            _json_skip!(p)
            key = _json_string!(p)
            _json_skip!(p)
            p.index <= length(p.text) && p.text[p.index] == ':' || throw(ArgumentError("expected JSON colon"))
            p.index += 1
            result[key] = _json_value!(p)
            _json_skip!(p)
            p.index <= length(p.text) || throw(ArgumentError("unexpected end of JSON object"))
            p.text[p.index] == '}' && (p.index += 1; return result)
            p.text[p.index] == ',' || throw(ArgumentError("expected JSON comma"))
            p.index += 1
        end
    elseif character == '['
        p.index += 1
        result = Any[]
        _json_skip!(p)
        p.index <= length(p.text) && p.text[p.index] == ']' && (p.index += 1; return result)
        while true
            push!(result, _json_value!(p))
            _json_skip!(p)
            p.index <= length(p.text) || throw(ArgumentError("unexpected end of JSON array"))
            p.text[p.index] == ']' && (p.index += 1; return result)
            p.text[p.index] == ',' || throw(ArgumentError("expected JSON comma"))
            p.index += 1
        end
    end
    start = p.index
    while p.index <= length(p.text) && !(p.text[p.index] in (',', '}', ']', ' ', '\n', '\r', '\t')); p.index += 1; end
    token = String(p.text[start:p.index-1])
    token == "true" && return true
    token == "false" && return false
    token == "null" && return nothing
    occursin(r"^-?[0-9]+$", token) && return parse(Int, token)
    occursin(r"^-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$", token) && return parse(Float64, token)
    occursin(r"^-?[0-9]+[eE][+-]?[0-9]+$", token) && return parse(Float64, token)
    throw(ArgumentError("invalid JSON value"))
end

function _json_encode(value)
    value === nothing && return "null"
    value === true && return "true"
    value === false && return "false"
    value isa Symbol && return _json_encode(string(value))
    value isa AbstractString && begin
        io = IOBuffer()
        write(io, '"')
        for character in value
            character == '"' ? write(io, "\\\"") : character == '\\' ? write(io, "\\\\") :
            character == '\n' ? write(io, "\\n") : character == '\r' ? write(io, "\\r") :
            character == '\t' ? write(io, "\\t") : Int(character) < 0x20 ? write(io, "\\u", lpad(string(Int(character), base=16), 4, '0')) : write(io, character)
        end
        write(io, '"')
        return String(take!(io))
    end
    if value isa Integer || value isa AbstractFloat
        return string(value)
    end
    value isa AbstractVector && return "[" * join(_json_encode.(value), ",") * "]"
    value isa AbstractDict && return "{" * join([_json_encode(string(key)) * ":" * _json_encode(value[key]) for key in sort!(String[string(key) for key in keys(value)])], ",") * "}"
    _json_encode(string(value))
end

"Encode a versioned JSONL envelope with stable object-key ordering."
function encode_message(message::AbstractDict)
    haskey(message, "v") || haskey(message, :v) || throw(ArgumentError("protocol message requires v"))
    _json_encode(message) * "\n"
end

function decode_message(line::AbstractString; max_bytes=1024 * 1024)
    ncodeunits(line) <= max_bytes || throw(JuliaShellError(:message_too_large, "protocol message exceeds the size limit";
        details=Dict("max_bytes" => max_bytes), remediation="send a smaller request"))
    value = try
        parser = _JSONParser(collect(String(strip(line))), 1)
        parsed = _json_value!(parser)
        _json_skip!(parser)
        parser.index > length(parser.text) || throw(ArgumentError("trailing data after JSON message"))
        parsed
    catch err
        err isa JuliaShellError && rethrow()
        throw(JuliaShellError(:invalid_message, sprint(showerror, err);
            remediation="send one valid JSON object per line"))
    end
    value isa AbstractDict || throw(JuliaShellError(:invalid_message, "protocol message must be an object";
        remediation="send one valid JSON object per line"))
    version = get(value, "v", nothing)
    version == PROTOCOL_VERSION || throw(JuliaShellError(:protocol_version, "unsupported protocol version";
        details=Dict("received" => version, "supported" => PROTOCOL_VERSION), remediation="upgrade the client or daemon"))
    value
end

function _invalid_request(message; field=nothing, value=nothing)
    details = Dict{String,Any}()
    field === nothing || (details["field"] = String(field))
    value === nothing || (details["value"] = value)
    JuliaShellError(:invalid_request, String(message); details,
                    remediation="send a valid v$(PROTOCOL_VERSION) daemon request")
end

function validate_protocol_request(request::AbstractDict)
    get(request, "v", nothing) == PROTOCOL_VERSION ||
        throw(_invalid_request("request has an unsupported protocol version"; field="v",
                               value=get(request, "v", nothing)))
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
    if method in ("pins.pin", "pins.unpin")
        desktop_id = get(params, "desktop_id", nothing)
        desktop_id isa AbstractString && !isempty(strip(String(desktop_id))) ||
            throw(_invalid_request("desktop_id must be a non-empty string"; field="params.desktop_id", value=desktop_id))
    elseif method == "pins.reorder"
        for field in ("from", "to")
            value = get(params, field, nothing)
            value isa Integer && value > 0 ||
                throw(_invalid_request("reorder positions must be positive integers"; field="params.$field", value=value))
        end
    end
    if haskey(params, "if_revision")
        revision = params["if_revision"]
        revision isa Integer && revision >= 0 ||
            throw(_invalid_request("if_revision must be a non-negative integer"; field="params.if_revision", value=revision))
    end
    if haskey(params, "position")
        position = params["position"]
        position isa Integer && position > 0 ||
            throw(_invalid_request("position must be a positive integer"; field="params.position", value=position))
    end
    request
end

protocol_request(id, method, params=Dict{String,Any}()) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "method" => String(method), "params" => params)
protocol_response(id, result) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "ok" => true, "result" => result)
protocol_error(id, error) = Dict{String,Any}("v" => PROTOCOL_VERSION, "id" => String(id), "ok" => false, "error" => error)
protocol_event(event, revision, topics) = Dict{String,Any}("v" => PROTOCOL_VERSION, "event" => String(event), "revision" => Int(revision), "topics" => topics)

"Perform one request/response round trip over the per-user Unix socket."
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

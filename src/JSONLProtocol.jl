#=
JSONLProtocol — library-shaped JSON codec and framing boundary.

Provides a self-contained, bounded JSON parser/encoder and newline-delimited
JSONL (JSON Lines) framing.  This module has zero dependency on julia-shell
domain types, Protocol validation, or daemon semantics.

# Public API

- `CodecError`: local failure type (no `JuliaShellError` dependency).
- `decode_json(payload)`: parse one bounded JSON value.
- `json_encode(value)`: encode a Julia value to a JSON string.
- `jsonl_encode(message)`: encode a dict to a newline-terminated JSONL line.
- `jsonl_decode(line)`: decode one JSONL line to a dict.
- `jsonl_decode_stream(io)`: decode a bounded sequence of JSONL messages.
- `PROTOCOL_VERSION`: protocol version constant (1).

# Extraction readiness

- Zero imports from julia-shell domain modules.
- Failure type (`CodecError`) defined locally.
- All public symbols documented with docstrings.
- Standalone test suite can exercise this module without JuliaShell.
=#

"""
    CodecError(code::Symbol, message::String; details=nothing, remediation=nothing)

A JSON codec or framing failure.  Structured to carry remediation hints without
depending on `JuliaShellError`.
"""
struct CodecError <: Exception
    code::Symbol
    message::String
    details::Union{Nothing,Dict{String,Any}}
    remediation::Union{Nothing,String}
end

function CodecError(code::Symbol, message::String;
                    details=nothing, remediation::Union{Nothing,String}=nothing)
    CodecError(code, String(message),
               details === nothing ? nothing : Dict{String,Any}(details),
               remediation)
end

function Base.showerror(io::IO, e::CodecError)
    print(io, "CodecError(", e.code, "): ", e.message)
    e.remediation !== nothing && print(io, " — ", e.remediation)
end

"Protocol version supported by this codec."
const PROTOCOL_VERSION = 1

# --- Internal JSON parser ---

mutable struct _JSONParser
    text::Vector{Char}
    index::Int
end

_json_skip!(p) = while p.index <= length(p.text) && p.text[p.index] in (' ', '\n', '\r', '\t'); p.index += 1; end

function _json_string!(p)
    p.text[p.index] == '"' || throw(ArgumentError("expected JSON string"))
    p.index += 1
    result = IOBuffer()
    while p.index <= length(p.text)
        character = p.text[p.index]
        p.index += 1
        character == '"' && return String(take!(result))
        Int(character) < 0x20 && throw(ArgumentError("unescaped control character in JSON string"))
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
            haskey(result, key) && throw(ArgumentError("duplicate JSON object key: $key"))
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
    occursin(r"^-?(0|[1-9][0-9]*)$", token) && return parse(Int, token)
    occursin(r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?[eE][+-]?[0-9]+$", token) && return parse(Float64, token)
    occursin(r"^-?(0|[1-9][0-9]*)\.[0-9]+$", token) && return parse(Float64, token)
    throw(ArgumentError("invalid JSON value"))
end

"""
    decode_json(payload::AbstractString; max_bytes=1024*1024)

Decode one bounded JSON value.  Rejects payloads exceeding `max_bytes`.
Returns a Julia value (Dict, Vector, String, Int, Float64, Bool, or Nothing).
"""
function decode_json(payload::AbstractString; max_bytes=1024 * 1024)
    max_bytes > 0 || throw(ArgumentError("max_bytes must be positive"))
    ncodeunits(payload) <= max_bytes || throw(CodecError(:message_too_large,
        "JSON value exceeds the size limit"; details=Dict("max_bytes" => max_bytes),
        remediation="send a smaller value"))
    parser = _JSONParser(collect(String(strip(payload))), 1)
    value = _json_value!(parser)
    _json_skip!(parser)
    parser.index > length(parser.text) || throw(ArgumentError("trailing data after JSON value"))
    value
end

# --- JSON encoder ---

"""
    json_encode(value) -> String

Encode a Julia value to a JSON string.  Handles nothing, booleans, integers,
floats, strings, vectors, and dictionaries with stable key ordering.
"""
function json_encode(value)
    value === nothing && return "null"
    value === true && return "true"
    value === false && return "false"
    value isa Symbol && return json_encode(string(value))
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
    if value isa AbstractFloat
        isfinite(value) || throw(ArgumentError("JSON cannot encode non-finite numbers"))
        return string(value)
    end
    if value isa Integer
        return string(value)
    end
    value isa AbstractVector && return "[" * join(json_encode.(value), ",") * "]"
    if value isa AbstractDict
        pairs = Pair{String,Any}[string(key) => item for (key, item) in value]
        length(unique(first.(pairs))) == length(pairs) ||
            throw(ArgumentError("JSON object keys must be unique after string conversion"))
        sort!(pairs; by=first)
        return "{" * join([json_encode(key) * ":" * json_encode(item) for (key, item) in pairs], ",") * "}"
    end
    json_encode(string(value))
end

# --- JSONL framing ---

"""
    jsonl_encode(message::AbstractDict) -> String

Encode a dict to a newline-terminated JSONL line.  The message must contain
a `v` (version) key.
"""
function jsonl_encode(message::AbstractDict)
    haskey(message, "v") || haskey(message, :v) || throw(ArgumentError("protocol message requires v"))
    json_encode(message) * "\n"
end

"""
    jsonl_decode(line::AbstractString; max_bytes=1024*1024) -> Dict{String,Any}

Decode one JSONL line to a dict.  Validates that the payload is a JSON object.
"""
function jsonl_decode(line::AbstractString; max_bytes=1024 * 1024)
    value = try
        decode_json(line; max_bytes)
    catch err
        err isa CodecError && rethrow()
        throw(CodecError(:invalid_message, sprint(showerror, err);
            remediation="send one valid JSON object per line"))
    end
    value isa AbstractDict || throw(CodecError(:invalid_message, "protocol message must be an object";
        remediation="send one valid JSON object per line"))
    Dict{String,Any}(String(k) => v for (k, v) in value)
end

function _readline_bounded(io::IO, max_bytes::Integer)
    max_bytes > 0 || throw(ArgumentError("max_bytes must be positive"))
    bytes = UInt8[]
    while true
        eof(io) && return isempty(bytes) ? nothing : String(bytes)
        byte = read(io, UInt8)
        byte == UInt8('\n') && return String(bytes)
        if length(bytes) >= max_bytes
            while !eof(io) && read(io, UInt8) != UInt8('\n')
            end
            throw(CodecError(:message_too_large, "JSONL line exceeds the size limit";
                details=Dict("max_bytes" => max_bytes), remediation="send a smaller message"))
        end
        push!(bytes, byte)
    end
end

"""
    jsonl_decode_stream(io::IO; max_messages=1024, max_bytes=1024*1024)

Decode non-empty JSONL lines from `io` into a bounded vector.  Each line is
limited to `max_bytes` and the stream is limited to `max_messages` messages.
"""
function jsonl_decode_stream(io::IO; max_messages=1024, max_bytes=1024 * 1024)
    max_messages >= 0 || throw(ArgumentError("max_messages must be non-negative"))
    messages = Dict{String,Any}[]
    while true
        line = _readline_bounded(io, max_bytes)
        line === nothing && break
        isempty(strip(line)) && continue
        length(messages) < max_messages || throw(CodecError(:message_limit,
            "JSONL stream contains too many messages";
            details=Dict("max_messages" => max_messages),
            remediation="split the work across multiple connections"))
        push!(messages, jsonl_decode(line; max_bytes))
    end
    messages
end

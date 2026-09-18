using Test

# This file intentionally loads only the codec. It must not require JuliaShell,
# Protocol, daemon state, or any product policy.
module StandaloneJSONLProtocol
include(joinpath(@__DIR__, "..", "src", "JSONLProtocol.jl"))
end

@testset "standalone JSONL protocol" begin
    codec = StandaloneJSONLProtocol
    message = Dict{String,Any}("v" => 1, "id" => "one", "ok" => true,
                               "params" => Dict("count" => 2))
    encoded = codec.jsonl_encode(message)
    @test endswith(encoded, "\n")
    @test codec.jsonl_decode(encoded)["params"]["count"] == 2
    @test_throws codec.CodecError codec.jsonl_decode("not-json")
    @test codec.jsonl_decode(codec.jsonl_encode(Dict{Symbol,Any}(:v => 1, :id => "symbol")))["id"] == "symbol"
    @test_throws ArgumentError codec.json_encode(Dict{Any,Any}("v" => 1, :v => 2))
    @test_throws ArgumentError codec.json_encode(NaN)
    @test_throws ArgumentError codec.json_encode(Inf)

    ordered = Dict{String,Any}()
    ordered["z"] = 1
    ordered["a"] = Dict("b" => 2, "a" => 1)
    @test codec.json_encode(ordered) == "{\"a\":{\"a\":1,\"b\":2},\"z\":1}"
    @test_throws codec.CodecError codec.jsonl_decode("{\"v\":1,\"v\":2}")
    @test_throws codec.CodecError codec.jsonl_decode("{\"v\":1,\"x\":\"a\nb\"}")
    for invalid_number in ("01", "-01", "+1", ".1", "1.", "1e", "NaN")
        @test_throws codec.CodecError codec.jsonl_decode("{\"v\":1,\"x\":$invalid_number}")
    end
    @test codec.decode_json("-1.25E+3") == -1250.0
    @test codec.decode_json("\"é\""; max_bytes=4) == "é"
    @test_throws codec.CodecError codec.decode_json("\"é\""; max_bytes=3)
    @test_throws ArgumentError codec.decode_json("null"; max_bytes=0)

    stream = IOBuffer(encoded * codec.jsonl_encode(message))
    @test length(codec.jsonl_decode_stream(stream; max_messages=2)) == 2
    @test_throws codec.CodecError codec.jsonl_decode_stream(
        IOBuffer(encoded * encoded); max_messages=1)
    @test_throws codec.CodecError codec.jsonl_decode_stream(
        IOBuffer(encoded); max_bytes=4)
    recovery = IOBuffer("xxxxxxxx\n" * encoded)
    @test_throws codec.CodecError codec.jsonl_decode_stream(recovery; max_bytes=4)
    @test codec.jsonl_decode_stream(recovery; max_bytes=512)[1]["id"] == "one"
    malformed = IOBuffer("{broken}\n" * encoded)
    @test_throws codec.CodecError codec.jsonl_decode_stream(malformed)
    @test codec.jsonl_decode_stream(malformed)[1]["id"] == "one"
    @test_throws ArgumentError codec.jsonl_decode_stream(IOBuffer(); max_messages=-1)
    @test_throws ArgumentError codec.jsonl_decode_stream(IOBuffer(); max_bytes=0)
end

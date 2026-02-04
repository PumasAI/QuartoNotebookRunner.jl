# JSON message handling for socket interface.

"""
    HMACMismatchError

Thrown when HMAC validation fails for incoming messages.
"""
struct HMACMismatchError <: Exception end

_key_to_hmac_bytes(key::Base.UUID) = Vector{UInt8}(string(key))

"""
    _read_json(key::Base.UUID, data)

Parse and validate a signed JSON message. Verifies HMAC before returning payload.
"""
function _read_json(key::Base.UUID, data)
    obj = JSON3.read(data, @NamedTuple{hmac::String, payload::String})
    hmac = obj.hmac
    payload = obj.payload

    hmac_vec_client = Base64.base64decode(hmac)
    hmac_vec_server = SHA.hmac_sha256(_key_to_hmac_bytes(key), payload)
    if !isequal_constant_time(hmac_vec_client, hmac_vec_server)
        throw(HMACMismatchError())
    end

    return JSON3.read(
        payload,
        @NamedTuple{type::String, content::Union{String,Dict{String,Any}}}
    )
end

# https://codahale.com/a-lesson-in-timing-attacks/
@noinline function isequal_constant_time(v1::Vector{UInt8}, v2::Vector{UInt8})::Bool
    length(v1) != length(v2) && return false
    result = 0
    for (a, b) in zip(v1, v2)
        result |= a ⊻ b
    end
    return result == 0
end

"""
    _write_hmac_json(socket, key::Base.UUID, data)

Write signed JSON message with HMAC.
"""
function _write_hmac_json(socket, key::Base.UUID, data)
    payload = JSON3.write(data)
    hmac = SHA.hmac_sha256(_key_to_hmac_bytes(key), payload)
    hmac_b64 = Base64.base64encode(hmac)
    write(socket, JSON3.write((; hmac = hmac_b64, payload)), "\n")
    flush(socket)
end

"""
    _write_json(socket, data)

Write JSON message without signing.
"""
function _write_json(socket, data)
    write(socket, JSON3.write(data), "\n")
    flush(socket)
end

"""
    _get_file(content)

Extract file path from request content.
"""
function _get_file(content::Dict)
    if haskey(content, "file")
        return content["file"]
    else
        error("No 'file' key in content: $(repr(content))")
    end
end
_get_file(content::String) = content

"""
    _get_options(content)

Extract options from request content.
"""
_get_options(content::Dict) = get(content, "options", Dict{String,Any}())
_get_options(::String) = Dict{String,Any}()

"""
    _get_source_ranges(content)

Extract source range mappings from request content.
"""
function _get_source_ranges(content::Dict)
    ranges = get(content, "sourceRanges", nothing)
    ranges === nothing && return nothing
    return map(ranges) do range
        file = get(range, "file", nothing)
        _lines::Vector{Int} = range["lines"]
        length(_lines) == 2 || error("sourceRanges lines must be 2-element array")
        lines = _lines[1]:_lines[2]
        _source_lines::Union{Nothing,Vector{Int}} = get(range, "sourceLines", nothing)
        source_lines = if _source_lines === nothing
            1:length(lines) # source lines are only missing in degenerate cases like additional newlines anyway so this doesn't really matter
        else
            length(_source_lines) == 2 ||
                error("sourceRanges sourceLines must be 2-element array")
            _source_lines[1]:_source_lines[2]
        end
        SourceRange(file, lines, source_lines)
    end
end
_get_source_ranges(::String) = nothing

"""
    _get_nested(d::Dict, keys...)

Get a deeply nested value from a dictionary.
"""
function _get_nested(d::Dict, keys...)
    _d = d
    for key in keys
        _d = get(_d, key, nothing)
        _d === nothing && return
    end
    return _d
end

"""
    _get_markdown(options)

Extract markdown content from options.
"""
_get_markdown(options::Dict)::Union{Nothing,String} =
    _get_nested(options, "target", "markdown", "value")

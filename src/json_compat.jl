# Typed JSON reading across both supported `JSON` versions.
#
# `JSON` v1 needs julia 1.9, so julia 1.6 resolves v0.21, which has no typed
# parsing at all. Each reader below returns the same type under either version:
# v1 parses straight into it, v0.21 parses generically and converts.

const CacheEntry =
    @NamedTuple{timestamp::Dates.DateTime, file::String, qnr_schema_version::VersionNumber}
const CachedCells = @NamedTuple{cells::Vector{Any}, qnr_schema_version::VersionNumber}
const SignedMessage = @NamedTuple{hmac::String, payload::String}

@static if isdefined(Base, :pkgversion) && Base.pkgversion(JSON) >= v"1"
    _read_cache_entry(file::AbstractString) = JSON.parsefile(file, CacheEntry)

    _read_cached_cells(file::AbstractString) = JSON.parsefile(file, CachedCells)

    _read_string_list(str::AbstractString) = JSON.parse(str, Vector{String})

    _read_signed_message(data) = JSON.parse(data, SignedMessage)
else
    function _read_cache_entry(file::AbstractString)
        json = JSON.parsefile(file; dicttype = Dict{String,Any})
        return CacheEntry((
            Dates.DateTime(json["timestamp"]),
            json["file"],
            VersionNumber(json["qnr_schema_version"]),
        ))
    end

    function _read_cached_cells(file::AbstractString)
        json = JSON.parsefile(file; dicttype = Dict{String,Any})
        return CachedCells((json["cells"], VersionNumber(json["qnr_schema_version"])))
    end

    _read_string_list(str::AbstractString) = convert(Vector{String}, JSON.parse(str))

    function _read_signed_message(data)
        json = JSON.parse(data; dicttype = Dict{String,Any})
        return SignedMessage((json["hmac"], json["payload"]))
    end
end

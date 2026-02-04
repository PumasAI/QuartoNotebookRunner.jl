# Notebook output caching.

const SCHEMA_VERSION = v"1.0.0"
const MAX_CACHE_ENTRIES_PER_NOTEBOOK = 3

"""
    _cache_file(f::File, source_code_hash)

Compute the cache file path for a notebook based on its manifest and source hash.
"""
function _cache_file(f::File, source_code_hash)
    path = joinpath(dirname(f.path), ".cache")
    hs = string(hash(f.worker.manifest_file, source_code_hash); base = 62)
    return joinpath(path, "$(basename(f.path)).$hs.json")
end

"""
    _gc_cache_files(dir::AbstractString)

Garbage collect old cache files, keeping only the 3 most recent per notebook.
"""
function _gc_cache_files(dir::AbstractString)
    # Check all available caches, removing all but the 3 most recent per qmd file.
    if isdir(dir)
        EntryT = @NamedTuple{
            timestamp::Dates.DateTime,
            file::String,
            qnr_schema_version::VersionNumber,
        }
        CachesT = Vector{EntryT}
        qmds = Dict{String,CachesT}()
        for file in readdir(dir; join = true)
            if endswith(file, ".json")
                try
                    json = JSON3.read(file, EntryT)
                    caches = get!(CachesT, qmds, json.file)
                    push!(caches, (; json..., file))
                catch error
                    @debug "invalid cache file, skipping" error
                end
            end
        end
        for v in values(qmds)
            sort!(v, by = x -> x.timestamp, rev = true)
            for each in v[(MAX_CACHE_ENTRIES_PER_NOTEBOOK+1):end]
                rm(each.file; force = true)
            end
        end
    end
end

"""
    load_from_file!(f::File, source_code_hash)

Load cached outputs from disk if available and source hash matches.
"""
function load_from_file!(f::File, source_code_hash)
    # Only load from file cache on initial load, not once the file is populated
    # with chunks.
    if isempty(f.output_chunks)
        file = _cache_file(f, source_code_hash)
        if isfile(file)
            try
                json = JSON3.read(
                    file,
                    @NamedTuple{
                        cells::Vector{NamedTuple},
                        qnr_schema_version::VersionNumber,
                    }
                )
                if json.qnr_schema_version == SCHEMA_VERSION
                    f.output_chunks = json.cells
                    f.source_code_hash = source_code_hash
                else
                    @debug "cache schema version mismatch" json.qnr_schema_version SCHEMA_VERSION
                end
            catch error
                @debug "invalid cache file, skipping" error
            end
        end
        # Perform a garbage collection of the oldest cache files.
        _gc_cache_files(dirname(file))
    end
    return nothing
end

"""
    save_to_file!(f::File)

Save notebook outputs to the cache file.
"""
function save_to_file!(f::File)
    file = _cache_file(f, f.source_code_hash)
    mkpath(dirname(file))
    json = (;
        cells = f.output_chunks,
        timestamp = Dates.now(),
        file = f.path,
        qnr_schema_version = SCHEMA_VERSION,
    )
    write_json(file, json)
end

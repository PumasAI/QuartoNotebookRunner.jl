# Core type definitions for QuartoNotebookRunner.

"""
    WorkerKey

Identifies a shared worker configuration. Notebooks with matching WorkerKeys
can share the same worker process.
"""
struct WorkerKey
    exe::Cmd
    exeflags::Vector{String}
    env::Vector{String}
    strict_manifest_versions::Bool
end

Base.hash(k::WorkerKey, h::UInt) =
    hash(k.strict_manifest_versions, hash(k.env, hash(k.exeflags, hash(k.exe, h))))
Base.:(==)(a::WorkerKey, b::WorkerKey) =
    a.exe == b.exe &&
    a.exeflags == b.exeflags &&
    a.env == b.env &&
    a.strict_manifest_versions == b.strict_manifest_versions

"""
    SharedWorkerEntry

Tracks a shared worker process and which notebooks are using it.
"""
mutable struct SharedWorkerEntry
    worker::WorkerIPC.Worker
    users::Set{String}  # notebook paths using this worker
end

"""
    FileState

File lifecycle states. All transitions happen under `file.lock`.
"""
module FileState
@enum T begin
    Ready
    Running
    Closing
end
end

"""
    File

Represents a notebook file managed by a Server. Tracks the worker process,
execution state, and cached outputs.
"""
mutable struct File
    worker::WorkerIPC.Worker              # Worker process for notebook execution
    path::String                          # Absolute path to notebook file
    source_code_hash::UInt64              # Hash of executable code for caching
    output_chunks::Vector                 # Cached cell outputs from last run
    exe::Cmd                              # Julia executable command
    exeflags::Vector{String}              # Julia command-line flags
    env::Vector{String}                   # Environment variables for worker
    strict_manifest_versions::Bool        # Require exact patch version match
    lock::ReentrantLock                   # Protects concurrent access
    timeout::Float64                      # Seconds until auto-close (0 = immediate)
    timeout_timer::Union{Nothing,Timer}   # Active timeout timer
    run_started::Union{Nothing,Dates.DateTime}   # Last run start time
    run_finished::Union{Nothing,Dates.DateTime}  # Last run completion time
    force_close_requested::Threads.Atomic{Bool} # Set by forceclose!, checked by run!
    sandbox_base::String                  # Shared sandbox base from Server
    worker_key::Union{Nothing,WorkerKey}  # Non-nothing when using a shared worker
    state::FileState.T                    # Lifecycle state (Ready, Running, Closing)

    function File(
        path::String,
        options::Union{String,Dict{String,Any}};
        sandbox_base,
        worker::Union{Nothing,WorkerIPC.Worker} = nothing,
        worker_key::Union{Nothing,WorkerKey} = nothing,
    )
        if isfile(path)
            _, ext = splitext(path)
            if ext in (".jl", ".qmd")
                path = isabspath(path) ? path : abspath(path)

                options = _parsed_options(options)
                _, _, file_frontmatter = raw_text_chunks(path)
                merged_options = _extract_relevant_options(file_frontmatter, options)
                exeflags, env, quarto_env = _exeflags_and_env(merged_options)
                timeout = _extract_timeout(merged_options)
                julia_config = julia_worker_config(merged_options)

                exe, _exeflags = _julia_exe(exeflags)
                if worker === nothing
                    worker = _start_worker(;
                        exe,
                        exeflags = _exeflags,
                        env = vcat(env, quarto_env),
                        strict_manifest_versions = julia_config.strict_manifest_versions,
                        sandbox_base,
                        notebook_dir = dirname(path),
                    )
                end
                file = new(
                    worker,
                    path,
                    hash(VERSION),
                    [],
                    exe,
                    exeflags,
                    env,
                    julia_config.strict_manifest_versions,
                    ReentrantLock(),
                    timeout,
                    nothing,
                    nothing,
                    nothing,
                    Threads.Atomic{Bool}(false),
                    sandbox_base,
                    worker_key,
                    FileState.Ready,
                )
                init!(file, merged_options)
                return file
            else
                throw(
                    ArgumentError(
                        "file is not a julia script or quarto markdown file: $path",
                    ),
                )
            end
        else
            throw(ArgumentError("file does not exist: $path"))
        end
    end
end

# Valid state transitions for File lifecycle.
const VALID_TRANSITIONS = Set{Tuple{FileState.T,FileState.T}}([
    (FileState.Ready, FileState.Running),
    (FileState.Running, FileState.Ready),
    (FileState.Running, FileState.Closing),
    (FileState.Ready, FileState.Closing),
])

"""
    transition!(file, from, to)

Transition a File's lifecycle state. Validates that the current state matches
`from` and that `from → to` is a valid transition. All calls must be made
under `file.lock`.
"""
function transition!(file::File, from::FileState.T, to::FileState.T)
    file.state === from || error("Expected $(file.path) in state $from, got $(file.state)")
    (from, to) in VALID_TRANSITIONS ||
        error("Invalid state transition $from → $to for $(file.path)")
    file.state = to
    @debug "$(basename(file.path)): $from → $to"
    return nothing
end

struct Server
    workers::Dict{String,File}
    shared_workers::Dict{WorkerKey,SharedWorkerEntry}
    lock::ReentrantLock # should be locked for mutation/lookup of the workers dict, not for evaling on the workers. use worker locks for that
    on_change::Base.RefValue{Function} # an optional callback function n_workers::Int -> nothing that gets called with the server.lock locked when workers are added or removed
    sandbox_base::String # shared temp dir for worker sandboxes, cleaned on Server close
    function Server()
        workers = Dict{String,File}()
        shared_workers = Dict{WorkerKey,SharedWorkerEntry}()
        sandbox_base = joinpath(
            WorkerIPC._get_scratchspace_path(),
            "sandboxes",
            string(rand(UInt), base = 62),
        )
        mkpath(sandbox_base)
        return new(
            workers,
            shared_workers,
            ReentrantLock(),
            Ref{Function}(identity),
            sandbox_base,
        )
    end
end

function on_change(s::Server)
    s.on_change[](length(s.workers))
    return
end

"""
    SourceRange

Maps notebook lines to source file locations for error reporting.
"""
struct SourceRange
    file::Union{String,Nothing}
    lines::UnitRange{Int}
    source_line::Union{Nothing,Int}
end

function SourceRange(file, lines, source_lines::UnitRange)
    if length(lines) != length(source_lines)
        error(
            "Mismatching lengths of lines $lines ($(length(lines))) and source_lines $source_lines ($(length(source_lines)))",
        )
    end
    SourceRange(file, lines, first(source_lines))
end

"""
    Unset

Sentinel type for cell options that haven't been explicitly set.
"""
struct Unset end

"""
    EvaluationError

Thrown when notebook evaluation encounters errors.
Contains metadata about each error including location and traceback.
"""
struct EvaluationError <: Exception
    metadata::Vector{NamedTuple{(:kind, :file, :traceback),Tuple{Symbol,String,String}}}
end

function Base.showerror(io::IO, e::EvaluationError)
    println(
        io,
        "EvaluationError: Encountered $(length(e.metadata)) error$(length(e.metadata) == 1 ? "" : "s") during evaluation",
    )
    for (i, meta) in enumerate(e.metadata)
        println(io)
        println(io, "Error ", i, " of ", length(e.metadata))
        println(io, "@ ", meta.file)
        println(io, meta.traceback)
    end
end

"""
    NoFileEntryError

Thrown when attempting to access a file not loaded in the server.
"""
struct NoFileEntryError <: Exception
    path::String
end

"""
    FileBusyError

Thrown when attempting to access a file whose worker is busy.
"""
struct FileBusyError <: Exception
    path::String
end

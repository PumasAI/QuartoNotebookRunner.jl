# Core type definitions for QuartoNotebookRunner.

"""
    File

Represents a notebook file managed by a Server. Tracks the worker process,
execution state, and cached outputs.
"""
mutable struct File
    worker::WorkerIPC.Worker
    path::String
    source_code_hash::UInt64
    output_chunks::Vector
    exe::Cmd
    exeflags::Vector{String}
    env::Vector{String}
    lock::ReentrantLock
    timeout::Float64
    timeout_timer::Union{Nothing,Timer}
    run_started::Union{Nothing,Dates.DateTime}
    run_finished::Union{Nothing,Dates.DateTime}
    run_decision_channel::Channel{Symbol}

    function File(path::String, options::Union{String,Dict{String,Any}})
        if isfile(path)
            _, ext = splitext(path)
            if ext in (".jl", ".qmd")
                path = isabspath(path) ? path : abspath(path)

                options = _parsed_options(options)
                _, _, file_frontmatter = raw_text_chunks(path)
                merged_options = _extract_relevant_options(file_frontmatter, options)
                exeflags, env, quarto_env = _exeflags_and_env(merged_options)
                timeout = _extract_timeout(merged_options)

                exe, _exeflags = _julia_exe(exeflags)
                worker = cd(
                    () -> WorkerIPC.Worker(;
                        exe,
                        exeflags = _exeflags,
                        env = vcat(env, quarto_env),
                    ),
                    dirname(path),
                )
                file = new(
                    worker,
                    path,
                    hash(VERSION),
                    [],
                    exe,
                    exeflags,
                    env,
                    ReentrantLock(),
                    timeout,
                    nothing,
                    nothing,
                    nothing,
                    Channel{Symbol}(32), # buffered to avoid blocking on put!
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

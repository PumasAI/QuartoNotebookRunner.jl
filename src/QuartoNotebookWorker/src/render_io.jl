# IO capture and context for cell evaluation.

function io_capture(f; cell_options, kws...)
    # Extensions append themselves as they load, so anything past this mark
    # loaded while the cell ran.
    mark = length(LOADED_EXTENSIONS)
    captured = _capture(f; kws...)
    extensions = @view LOADED_EXTENSIONS[mark+1:end]
    warning = get(cell_options, "warning", true)
    return merge(
        captured,
        (; streams = _tidy_streams(captured.streams, extensions, warning)),
    )
end

# Quarto drops the `stderr` streams of a cell with `warning: false`, which would
# leave the `stdout` runs either side of each one as separate blocks, so the
# worker drops those streams itself and joins the runs that remain.
function _tidy_streams(streams, extensions, warning::Bool)
    tidied = Tuple{String,String}[]
    for (name, text) in streams
        warning || name == "stdout" || continue
        text = strip_worker_precompilation(text, extensions)
        isempty(text) && continue
        if !isempty(tidied) && first(tidied[end]) == name
            tidied[end] = (name, last(tidied[end]) * text)
        else
            push!(tidied, (name, text))
        end
    end
    return tidied
end

# What a cell wrote, as runs of consecutive writes to one stream, in the order
# they were written.
struct StreamRuns
    runs::Vector{Pair{String,IOBuffer}}
    lock::ReentrantLock
end
StreamRuns() = StreamRuns(Pair{String,IOBuffer}[], ReentrantLock())

function _record!(write_bytes, runs::StreamRuns, name::String)
    lock(runs.lock) do
        if isempty(runs.runs) || first(runs.runs[end]) != name
            push!(runs.runs, name => IOBuffer())
        end
        write_bytes(last(runs.runs[end]))
    end
end

_streams(runs::StreamRuns) = [(name, String(take!(buffer))) for (name, buffer) in runs.runs]

# One of the streams a cell writes to. A write from Julia is recorded as it
# happens, which is what keeps the order across streams. The file descriptor
# points at `pipe` instead, so writes from C libraries and subprocesses are
# recorded when the reader gets to them.
struct CapturedStream <: Base.AbstractPipe
    name::String
    pipe::Pipe
    runs::StreamRuns
end

Base.pipe_writer(stream::CapturedStream) = stream.pipe.in
Base.pipe_reader(stream::CapturedStream) = stream.pipe.out

Base.unsafe_write(stream::CapturedStream, p::Ptr{UInt8}, nb::UInt) =
    _record!(buffer -> unsafe_write(buffer, p, nb), stream.runs, stream.name)
Base.write(stream::CapturedStream, byte::UInt8) =
    _record!(buffer -> write(buffer, byte), stream.runs, stream.name)

function CapturedStream(name::String, runs::StreamRuns)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    return CapturedStream(name, pipe, runs)
end

function _read_pipe(stream::CapturedStream)
    while !eof(stream.pipe.out)
        bytes = readavailable(stream.pipe.out)
        _record!(buffer -> write(buffer, bytes), stream.runs, stream.name)
    end
end

@static if VERSION < v"1.7"
    # Julia 1.6 redirects only to a stream with a file descriptor. Given an
    # `IOContext` it redirects to what the context wraps, then points the global
    # at the context.
    Base.redirect_stdout(stream::CapturedStream) = redirect_stdout(Base.pipe_writer(stream))
    Base.redirect_stderr(stream::CapturedStream) = redirect_stderr(Base.pipe_writer(stream))
end

# Capture what the cell writes to `stdout`, `stderr` and the logger. The readers
# stop once the cell's code has returned rather than once the pipes reach their
# end: a process the cell started and left running holds a copy of the write
# ends, and would hold the cell open for as long as it runs.
#
# Derived from IOCapture.jl (MIT), which took it from Documenter.jl.
function _capture(f; rethrow::Type = Any, color::Bool = false, io_context = ())
    default_stdout = stdout
    default_stderr = stderr

    runs = StreamRuns()
    captured_stdout = CapturedStream("stdout", runs)
    captured_stderr = CapturedStream("stderr", runs)
    colored = get(default_stdout, :color, false) & color
    context_stdout = IOContext(captured_stdout, :color => colored, io_context...)
    context_stderr = IOContext(captured_stderr, :color => colored, io_context...)
    redirect_stdout(context_stdout)
    redirect_stderr(context_stderr)
    logger = Logging.ConsoleLogger(context_stderr)

    # A new task seeds its rng from the current task, which moves the stream the
    # cell's own code draws from, so put the seed back afterwards.
    @static if VERSION >= v"1.7"
        seed = copy(Random.default_rng())
    end
    readers = [@async(_read_pipe(captured_stdout)), @async(_read_pipe(captured_stderr))]
    @static if VERSION >= v"1.7"
        copy!(Random.default_rng(), seed)
    end

    value, errored, backtrace = Logging.with_logger(logger) do
        try
            # See https://github.com/JuliaDocs/Documenter.jl/issues/2121.
            yield()
            f(), false, Vector{Ptr{Cvoid}}()
        catch error
            error isa rethrow && Base.rethrow(error)
            error, true, catch_backtrace()
        finally
            redirect_stdout(default_stdout)
            redirect_stderr(default_stderr)
            pipes = [captured_stdout.pipe, captured_stderr.pipe]
            foreach(pipe -> close(pipe.in), pipes)
            _stop_reading(readers, pipes)
        end
    end

    return (; value, streams = _streams(runs), error = errored, backtrace)
end

# Closing the write ends ends the readers, unless a process the cell left
# running holds the other copy of one. Give the readers a moment to reach the
# end on their own, then close the read ends under them, which ends them with
# the output so far.
function _stop_reading(readers::Vector{Task}, pipes::Vector{Pipe}; grace::Real = 1)
    timer = Timer(grace) do _
        for (reader, pipe) in zip(readers, pipes)
            istaskdone(reader) || close(pipe.out)
        end
    end
    try
        for reader in readers
            try
                wait(reader)
            catch error
                error isa TaskFailedException || Base.rethrow(error)
            end
        end
    finally
        close(timer)
        foreach(close, pipes)
    end
    return nothing
end

# passing our module removes Main.Notebook noise when printing types etc.
function with_context(
    io::IO,
    mod::Module,
    cell_options = Dict{String,Any}(),
    inline = false,
)
    return IOContext(io, _io_context(mod, cell_options, inline)...)
end

function _io_context(mod::Module, cell_options = Dict{String,Any}(), inline = false)
    ctx = NotebookState.current_context()
    options = ctx === nothing ? Dict{String,Any}() : ctx.options

    return [
        :module => mod,
        :limit => true,
        :color => something(Base.have_color, false),
        # This allows a `show` method implementation to check for
        # metadata that may be of relevance to it's rendering. For
        # example, if a `typst` table is rendered with a caption
        # (available in the `cell_options`) then we need to adjust the
        # syntax that is output via the `QuartoNotebookRunner/typst`
        # show method to switch between `markdown` and `code` "mode".
        #
        # TODO: perhaps preprocess the metadata provided here rather
        # than just passing it through as-is.
        :QuartoNotebookRunner => (; cell_options, options, inline),
    ]
end

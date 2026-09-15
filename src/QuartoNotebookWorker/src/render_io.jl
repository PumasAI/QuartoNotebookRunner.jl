# IO capture and context for cell evaluation.

function io_capture(f; cell_options, kws...)
    warning = get(cell_options, "warning", true)
    capture() = _capture(f; kws...)
    # Extensions append themselves as they load, so anything past this mark
    # loaded while the cell ran.
    mark = length(LOADED_EXTENSIONS)
    captured = if warning
        capture()
    else
        logger = Logging.global_logger()
        current_level = Logging.min_enabled_level(logger)
        try
            Logging.disable_logging(Logging.Error)
            capture()
        finally
            Logging.disable_logging(current_level - 1)
        end
    end
    extensions = @view LOADED_EXTENSIONS[mark+1:end]
    return merge(
        captured,
        (; output = strip_worker_precompilation(captured.output, extensions)),
    )
end

# Capture what the cell writes to `stdout`, `stderr` and the logger. The reader
# stops once the cell's code has returned rather than once the pipe reaches its
# end: a process the cell started and left running holds a copy of the write
# end, and would hold the cell open for as long as it runs.
#
# Derived from IOCapture.jl (MIT), which took it from Documenter.jl.
function _capture(f; rethrow::Type = Any, color::Bool = false, io_context = ())
    default_stdout = stdout
    default_stderr = stderr

    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    colored = get(default_stdout, :color, false) & color
    pipe_stdout = IOContext(pipe.in, :color => colored, io_context...)
    pipe_stderr = IOContext(pipe.in, :color => colored, io_context...)
    redirect_stdout(pipe_stdout)
    redirect_stderr(pipe_stderr)
    logger = Logging.ConsoleLogger(pipe_stderr)

    buffer = IOBuffer()
    # A new task seeds its rng from the current task, which moves the stream the
    # cell's own code draws from, so put the seed back afterwards.
    @static if VERSION >= v"1.7"
        seed = copy(Random.default_rng())
        reader = @async write(buffer, pipe)
        copy!(Random.default_rng(), seed)
    else
        reader = @async write(buffer, pipe)
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
            close(pipe_stdout)
            close(pipe_stderr)
            _stop_reading(reader, pipe)
        end
    end

    return (; value, output = String(take!(buffer)), error = errored, backtrace)
end

# Closing the write end ends the reader, unless a process the cell left running
# holds the other copy of it. Give the reader a moment to reach the end on its
# own, then close the read end under it, which ends it with the output so far.
function _stop_reading(reader::Task, pipe::Pipe; grace::Real = 1)
    timer = Timer(grace) do _
        istaskdone(reader) || close(pipe.out)
    end
    try
        wait(reader)
    catch error
        error isa TaskFailedException || Base.rethrow(error)
    finally
        close(timer)
        close(pipe)
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

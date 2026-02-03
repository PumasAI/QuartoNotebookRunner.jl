# Types defined in types.jl
# Worker setup functions defined in worker_setup.jl

struct Server
    workers::Dict{String,File}
    lock::ReentrantLock # should be locked for mutation/lookup of the workers dict, not for evaling on the workers. use worker locks for that
    on_change::Base.RefValue{Function} # an optional callback function n_workers::Int -> nothing that gets called with the server.lock locked when workers are added or removed
    function Server()
        workers = Dict{String,File}()
        return new(workers, ReentrantLock(), Ref{Function}(identity))
    end
end

function on_change(s::Server)
    s.on_change[](length(s.workers))
    return
end

# Implementation.

function init!(file::File, options::Dict)
    worker = file.worker
    WorkerIPC.call(worker, WorkerIPC.WorkerInitRequest(path = file.path, options = options))
end

function refresh!(file::File, options::Dict)
    exeflags, env, quarto_env = _exeflags_and_env(options)
    if exeflags != file.exeflags || env != file.env || !WorkerIPC.isrunning(file.worker) # the worker might have been killed on another task
        WorkerIPC.stop(file.worker)
        exe, _exeflags = _julia_exe(exeflags)
        file.worker = cd(
            () -> WorkerIPC.Worker(;
                exe,
                exeflags = _exeflags,
                env = vcat(env, quarto_env),
            ),
            dirname(file.path),
        )
        file.exe = exe
        file.exeflags = exeflags
        file.env = env
        file.source_code_hash = hash(VERSION)
        file.output_chunks = []
        init!(file, options)
    end
    refresh_quarto_env_vars!(file, quarto_env)
    WorkerIPC.call(file.worker, WorkerIPC.WorkerRefreshRequest(options = options))
end

# Environment variables provided by Quarto may change between `quarto render`
# calls. To update them correctly in the worker process, we need to refresh
# them before each run.
function refresh_quarto_env_vars!(file::File, quarto_env)
    if !isempty(quarto_env)
        WorkerIPC.call(file.worker, WorkerIPC.SetEnvVarsRequest(vars = quarto_env))
    end
    return nothing
end

# Cache functions defined in cache.jl

"""
    evaluate!(f::File, [output])

Evaluate the code and markdown in `f` and return a vector of cells with the
results in all available mimetypes.

`output` can be a file path, or an IO stream.
`markdown` can be used to pass an override for the file content, which is used
    to pass the modified markdown that quarto creates after resolving shortcodes
"""
function evaluate!(
    f::File,
    output::Union{AbstractString,IO,Nothing} = nothing;
    showprogress = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
    chunk_callback = (i, n, c) -> nothing,
    markdown::Union{String,Nothing} = nothing,
    source_ranges::Union{Nothing,Vector} = nothing,
)
    _check_output_dst(output)

    options = _parsed_options(options)
    path = abspath(f.path)
    if isfile(path)
        source_code_hash, raw_chunks, file_frontmatter =
            raw_text_chunks(f, markdown; source_ranges)
        merged_options = _extract_relevant_options(file_frontmatter, options)

        # A change of parameter values must invalidate the source code hash.
        source_code_hash = hash(merged_options["params"], source_code_hash)

        refresh!(f, merged_options)

        enabled_cache = merged_options["format"]["execute"]["cache"] == true
        enabled_cache && load_from_file!(f, source_code_hash)

        # This is the results caching logic. When only the markdown has
        # changed, e.g. the hash of all executable code blocks is the same as
        # the previous run then we can reuse the previous cell outputs.
        # Additionally, if the currently cached chunks is empty then we have a
        # fresh session that has not yet populated the `output_chunks`.
        if enabled_cache &&
           source_code_hash == f.source_code_hash &&
           !isempty(f.output_chunks)
            @debug "reusing previous cell outputs"
            # All the executable code cells are the same as the previous
            # render, so all we need to do is iterate over the markdown code
            # (that doesn't contain inline executable code) and update the
            # markdown cells with the new content.
            lookup = Dict(string(nth) => chunk for (nth, chunk) in enumerate(raw_chunks))
            for output_chunk in f.output_chunks
                if haskey(lookup, output_chunk.id)
                    new_raw_chunk = lookup[output_chunk.id]
                    # Skip any markdown chunk if it contains potential inline
                    # executable code otherwise they would be replaced with
                    # their unexpanded raw chunk.
                    if !contains(new_raw_chunk.source, r"`{(?:julia|python|r)} ")
                        # Swap out any markdown chunks with their updated content.
                        new_source = process_cell_source(new_raw_chunk.source)
                        empty!(output_chunk.source)
                        append!(output_chunk.source, new_source)
                    end
                end
            end
            cells = f.output_chunks
        else
            @debug "evaluating new cell outputs"
            # When there has been any kind of change to any executable code
            # blocks then we perform a complete rerun of the notebook. Further
            # optimisations can be made to perform source code analysis in the
            # worker process to determine if which cells need to be
            # reevaluated.
            cells = evaluate_raw_cells!(
                f,
                raw_chunks,
                merged_options;
                showprogress,
                chunk_callback,
            )
            # Update the hash to the latest computed.
            f.source_code_hash = source_code_hash
            f.output_chunks = cells

            enabled_cache && save_to_file!(f)
        end

        version = _get_julia_version(f)
        data = (
            metadata = (
                kernelspec = (
                    display_name = "Julia $(version)",
                    language = "julia",
                    name = "julia-$(version)",
                ),
                kernel_info = (name = "julia",),
                language_info = (
                    name = "julia",
                    version = version,
                    codemirror_mode = "julia",
                ),
            ),
            nbformat = 4,
            nbformat_minor = 5,
            cells,
        )
        write_json(output, data)
    else
        throw(ArgumentError("file does not exist: $(path)"))
    end
end

# The version of `julia` for a particular notebook file might not be the same
# as the runner process, so query the worker for this value.
function _get_julia_version(f::File)
    cmd = `$(f.exe) --version`
    return last(split(readchomp(cmd)))
end

# Options functions defined in options.jl

function _check_output_dst(s::AbstractString)
    s = abspath(s)
    dir = dirname(s)
    isdir(dir) || throw(ArgumentError("directory does not exist: $(dir)"))
    return nothing
end
_check_output_dst(::Any) = nothing

function write_json(s::AbstractString, data)
    open(s, "w") do io
        write_json(io, data)
    end
end
write_json(io::IO, data) = JSON3.pretty(io, data)
write_json(::Nothing, data) = data

# Parsing functions defined in parsing.jl

# Convenience macro that outputs
# ```julia
# if showprogress
#     ProgressLogging.@progress exprs...
# else
#     exprs[end]
# end
# ```
# TODO: Upstream to ProgressLogging?
macro maybe_progress(showprogress, exprs...)
    if isempty(exprs)
        throw(ArgumentError("at least one expression required"))
    end
    expr = quote
        if $(showprogress)
            $ProgressLogging.@progress $(exprs...)
        else
            $(exprs[end])
        end
    end
    return esc(expr)
end

should_eval(chunk, global_eval::Bool) =
    chunk.type === :code &&
    (chunk.evaluate === true || (chunk.evaluate === Unset() && global_eval))

"""
    evaluate_raw_cells!(f::File, chunks::Vector)

Evaluate the raw cells in `chunks` and return a vector of cells with the results
in all available mimetypes.

The optional `chunk_callback` is called with `(i::Int, n::Int, chunk)` before a chunk is processed and is
intended for a progress update mechanism via the socket interface.
"""
function evaluate_raw_cells!(
    f::File,
    chunks::Vector,
    options::Dict;
    showprogress = true,
    chunk_callback = (i, n, c) -> nothing,
)
    evaluate_params!(f, options["params"])

    cells = []

    error_metadata = NamedTuple{(:kind, :file, :traceback),Tuple{Symbol,String,String}}[]
    allow_error_global = options["format"]["execute"]["error"]
    global_eval::Bool = options["format"]["execute"]["eval"]

    wd = try
        pwd()
    catch
        ""
    end
    header = "Running $(relpath(f.path, wd))"

    chunks_to_evaluate = sum(c -> should_eval(c, global_eval), chunks)
    ith_chunk_to_evaluate = 1

    @maybe_progress showprogress "$header" for (nth, chunk) in enumerate(chunks)
        if chunk.type === :code
            if !should_eval(chunk, global_eval)
                # Cells that are not evaluated are not executed, but they are
                # still included in the notebook.
                push!(
                    cells,
                    (;
                        id = string(nth),
                        cell_type = chunk.type,
                        metadata = (;),
                        source = process_cell_source(chunk.source),
                        outputs = [],
                        execution_count = 0,
                    ),
                )
            else
                chunk_callback(ith_chunk_to_evaluate, chunks_to_evaluate, chunk)
                ith_chunk_to_evaluate += 1

                source = transform_source(chunk)

                # Offset the line number by 1 to account for the triple backticks
                # that are part of the markdown syntax for code blocks.
                render_response = WorkerIPC.call(
                    f.worker,
                    WorkerIPC.RenderRequest(
                        code = source,
                        file = chunk.file,
                        line = chunk.line + 1,
                        cell_options = chunk.cell_options,
                    ),
                )
                worker_results = render_response.cells
                expand_cell = render_response.is_expansion

                # When the result of the cell evaluation is a cell expansion
                # then we insert the original cell contents before the expanded
                # cells as a mock cell similar to if it has `eval: false` set.
                if expand_cell
                    push!(
                        cells,
                        (;
                            id = string(nth),
                            cell_type = chunk.type,
                            metadata = (;),
                            source = process_cell_source(chunk.source),
                            outputs = [],
                            execution_count = 1,
                        ),
                    )
                end

                for (mth, remote) in enumerate(worker_results)
                    outputs = []
                    processed = process_results(remote.results)

                    # Should this notebook cell be allowed to throw an error? When
                    # not allowed, we log all errors don't generate an output.
                    allow_error_cell = get(remote.cell_options, "error", allow_error_global)

                    if isnothing(remote.error)
                        for display_result in remote.display_results
                            processed_display = process_results(display_result)
                            if !isempty(processed_display.data)
                                push!(
                                    outputs,
                                    (;
                                        output_type = "display_data",
                                        processed_display.data,
                                        processed_display.metadata,
                                    ),
                                )
                            end
                            if !isempty(processed_display.errors)
                                append!(outputs, processed_display.errors)
                                if !allow_error_cell
                                    for each_error in processed_display.errors
                                        file = "$(chunk.file):$(chunk.line)"
                                        traceback = join(each_error.traceback, "\n")
                                        push!(
                                            error_metadata,
                                            (; kind = :show, file, traceback),
                                        )
                                    end
                                end
                            end
                        end
                        if !isempty(processed.data)
                            push!(
                                outputs,
                                (;
                                    output_type = "execute_result",
                                    execution_count = 1,
                                    processed.data,
                                    processed.metadata,
                                ),
                            )
                        end
                    else
                        # These are errors arising from evaluation of the contents
                        # of a code cell, not from the `show` output of the values,
                        # which is handled separately below.
                        push!(
                            outputs,
                            (;
                                output_type = "error",
                                ename = remote.error,
                                evalue = get(processed.data, "text/plain", ""),
                                traceback = remote.backtrace,
                            ),
                        )
                        if !allow_error_cell
                            file = "$(chunk.file):$(chunk.line)"
                            traceback = join(remote.backtrace, "\n")
                            push!(error_metadata, (; kind = :cell, file, traceback))
                        end
                    end

                    if !isempty(remote.output)
                        pushfirst!(
                            outputs,
                            (;
                                output_type = "stream",
                                name = "stdout",
                                text = remote.output,
                            ),
                        )
                    end

                    # These are errors arising from the `show` output of the values
                    # generated by cells, not from the cell evaluation itself. So if
                    # something throws an error here then the user's `show` method
                    # has a bug.
                    if !isempty(processed.errors)
                        append!(outputs, processed.errors)
                        if !allow_error_cell
                            for each_error in processed.errors
                                file = "$(chunk.file):$(chunk.line)"
                                traceback = join(each_error.traceback, "\n")
                                push!(error_metadata, (; kind = :show, file, traceback))
                            end
                        end
                    end

                    cell_options = expand_cell ? remote.cell_options : Dict()

                    if chunk.language === :python
                        # Code cells always get the language of the notebook assigned, in this case julia,
                        # so to render an R formatted cell, we need to do a workaround. We push a cell before
                        # the actual code cell which contains a plain markdown block that wraps the code in ```r
                        # for the formatting.
                        push!(
                            cells,
                            (;
                                id = string(
                                    expand_cell ? string(nth, "_", mth) : string(nth),
                                    "_code_prefix",
                                ),
                                cell_type = :markdown,
                                metadata = (;),
                                source = process_cell_source(
                                    """
           ```python
           $(strip_cell_options(chunk.source))
           ```
           """,
                                    Dict(),
                                ),
                            ),
                        )
                        # We also need to hide the real code cell in this case, which contains possible formatting
                        # settings in its YAML front-matter and which can therefore not be omitted entirely.
                        cell_options["echo"] = false
                    end

                    if chunk.language === :r
                        # Code cells always get the language of the notebook assigned, in this case julia,
                        # so to render an R formatted cell, we need to do a workaround. We push a cell before
                        # the actual code cell which contains a plain markdown block that wraps the code in ```r
                        # for the formatting.
                        push!(
                            cells,
                            (;
                                id = string(
                                    expand_cell ? string(nth, "_", mth) : string(nth),
                                    "_code_prefix",
                                ),
                                cell_type = :markdown,
                                metadata = (;),
                                source = process_cell_source(
                                    """
           ```r
           $(strip_cell_options(chunk.source))
           ```
           """,
                                    Dict(),
                                ),
                            ),
                        )
                        # We also need to hide the real code cell in this case, which contains possible formatting
                        # settings in its YAML front-matter and which can therefore not be omitted entirely.
                        cell_options["echo"] = false
                    end

                    source = expand_cell ? remote.code : chunk.source

                    push!(
                        cells,
                        (;
                            id = expand_cell ? string(nth, "_", mth) : string(nth),
                            cell_type = chunk.type,
                            metadata = (;),
                            source = process_cell_source(source, cell_options),
                            outputs,
                            execution_count = 1,
                        ),
                    )
                end
            end
        elseif chunk.type === :markdown
            marker = r"{(?:julia|python|r)} "
            source = chunk.source
            if contains(chunk.source, r"`{(?:julia|python|r)} ")
                parser = Parser()
                for (node, enter) in parser(chunk.source)
                    if enter && node.t isa CommonMark.Code
                        if startswith(node.literal, marker)
                            source_code = replace(node.literal, marker => "")
                            if startswith(node.literal, "{r}")
                                source_code = wrap_with_r_boilerplate(source_code)
                            end
                            if startswith(node.literal, "{python}")
                                source_code = wrap_with_python_boilerplate(source_code)
                            end
                            # There should only ever be a single result from an
                            # inline evaluation since you can't pass cell
                            # options and so `expand` will always be `false`.
                            render_response = WorkerIPC.call(
                                f.worker,
                                WorkerIPC.RenderRequest(
                                    code = source_code,
                                    file = chunk.file,
                                    line = chunk.line,
                                    cell_options = Dict{String,Any}(),
                                    inline = true,
                                ),
                            )
                            render_response.is_expansion &&
                                error("inline code cells cannot be expanded")
                            remote = only(render_response.cells)
                            if !isnothing(remote.error)
                                # file location is not straightforward to determine with inline literals, but just printing the (presumably short)
                                # code back instead of a location should be quite helpful
                                push!(
                                    error_metadata,
                                    (;
                                        kind = :inline,
                                        file = "inline: `$(node.literal)`",
                                        traceback = join(remote.backtrace, "\n"),
                                    ),
                                )
                            else
                                processed = process_inline_results(remote.results)
                                source = replace(
                                    source,
                                    "`$(node.literal)`" => "$processed";
                                    count = 1,
                                )
                            end
                        end
                    end
                end
            end
            push!(
                cells,
                (;
                    id = string(nth),
                    cell_type = chunk.type,
                    metadata = (;),
                    source = process_cell_source(source),
                ),
            )
        else
            throw(ArgumentError("unknown chunk type: $(chunk.type)"))
        end
    end
    if !isempty(error_metadata)
        throw(EvaluationError(error_metadata))
    end

    return cells
end

function evaluate_params!(f, params::Dict{String})
    invalid_param_keys = filter(!Base.isidentifier, keys(params))
    if !isempty(invalid_param_keys)
        plu = length(invalid_param_keys) > 1
        throw(
            ArgumentError(
                "Found parameter key$(plu ? "s that are not " : " that is not a ") valid Julia identifier$(plu ? "s" : ""): $(join((repr(k) for k in invalid_param_keys), ", ", " and ")).",
            ),
        )
    end

    WorkerIPC.call(f.worker, WorkerIPC.EvaluateParamsRequest(params = params))
    return
end

# Cell processing functions defined in cell_processing.jl

function run!(
    server::Server,
    path::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    markdown::Union{Nothing,String} = nothing,
    showprogress::Bool = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
    chunk_callback = (i, n, c) -> nothing,
    source_ranges::Union{Nothing,Vector} = nothing,
)
    try
        borrow_file!(server, path; options, optionally_create = true) do file
            if file.timeout_timer !== nothing
                close(file.timeout_timer)
                file.timeout_timer = nothing
            end
            file.run_started = Dates.now()
            file.run_finished = nothing

            # Run evaluate! in a task so we can detect force-close requests.
            # The forceclose! function will directly stop the worker if needed.
            result_task = Threads.@spawn begin
                try
                    evaluate!(
                        file,
                        output;
                        showprogress,
                        options,
                        markdown,
                        chunk_callback,
                        source_ranges,
                    )
                finally
                    put!(file.run_decision_channel, :evaluate_finished)
                end
            end

            # block until a decision is reached
            decision = take!(file.run_decision_channel)

            # forceclose! directly kills the worker, so check if it's still running.
            # This handles the race where we got :evaluate_finished but the worker
            # was killed by forceclose! before or during evaluation completion.
            if !WorkerIPC.isrunning(file.worker)
                error("File was force-closed during run")
            end

            if decision === :forceclose
                # Worker already stopped by forceclose!, just error out
                error("File was force-closed during run")
            elseif decision === :evaluate_finished
                result = try
                    fetch(result_task)
                catch err
                    # throw the original exception, not the wrapping TaskFailedException
                    rethrow(err.task.exception)
                end
            else
                error("Invalid decision $decision")
            end

            file.run_finished = Dates.now()
            if file.timeout > 0
                file.timeout_timer = Timer(file.timeout) do _
                    close!(server, file.path)
                    @debug "File at $(file.path) timed out after $(file.timeout) seconds of inactivity."
                end
            else
                close!(server, file.path)
            end
            return result
        end
    catch err
        if err isa FileBusyError
            throw(
                UserError(
                    "Tried to run file \"$path\" but the corresponding worker is busy.",
                ),
            )
        else
            rethrow(err)
        end
    end
end

"""
    borrow_file!(f, server, path; wait = false, optionally_create = false, options = Dict{String,Any}())

Executes `f(file)` while the `file`'s `ReentrantLock` is locked.
All actions on a `Server`'s `File` should be wrapped in this
so that no two tasks can mutate the `File` at the same time.
When `optionally_create` is `true`, the `File` will be created on the server
if it doesn't exist, in which case it is passed `options`.
If `wait = false`, `borrow_file!` will throw a `FileBusyError` if the lock cannot be attained immediately.
"""
function borrow_file!(
    f,
    server,
    path;
    wait = false,
    optionally_create = false,
    options = Dict{String,Any}(),
)
    apath = abspath(path)

    prelocked, file = lock(server.lock) do
        if haskey(server.workers, apath)
            return false, server.workers[apath]
        else
            if optionally_create
                # it's not ideal to create the `File` under server.lock but it takes a second or
                # so on my machine to init it, so for practical purposes it should be ok
                file = server.workers[apath] = File(apath, options)
                lock(file.lock) # don't let anything get to the fresh file before us
                on_change(server)
                return true, file
            else
                throw(NoFileEntryError(apath))
            end
        end
    end

    if prelocked
        return try
            f(file)
        finally
            unlock(file.lock)
        end
    else
        # we will now try to attain the lock of a previously existing file. once we have attained
        # it though, it could be that the file is stale because it has been
        # removed and possibly reopened in the meantime. So if
        # no file exists or it doesn't match the one we have, we recurse into `borrow_file!`.
        # This could in principle go on forever but is very unlikely to with a small number of
        # concurrent users.

        if wait
            lock(file.lock)
            lock_attained = true
        else
            lock_attained = trylock(file.lock)
        end

        try
            if !lock_attained
                throw(FileBusyError(apath))
            end
            current_file = lock(server.lock) do
                get(server.workers, apath, nothing)
            end
            if file !== current_file
                return borrow_file!(f, server, apath; options, optionally_create)
            else
                return f(file)
            end
        finally
            lock_attained && unlock(file.lock)
        end
    end
end

"""
    render(file::AbstractString; output::Union{AbstractString,IO,Nothing} = nothing, showprogress::Bool = true)

Render the notebook in `file` and write the results to `output`. Uses a similar
API to `run!` but does not keep the file loaded in a server and shuts down
immediately after rendering. This means that the user pays the full cost of
initial startup each time they render a notebook. Prefer `run!` if you are going
to be rendering the same notebook multiple times iteratively.
"""
function render(
    file::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    showprogress::Bool = true,
)
    server = Server()
    run!(server, file; output, showprogress)
    close!(server, file)
end

function close!(server::Server)
    lock(server.lock) do
        for path in keys(server.workers)
            close!(server, path)
        end
    end
end

"""
    close!(server::Server, path::String)

Closes the `File` at `path`. Returns `true` if the
file was closed and `false` if it did not exist, which
can happen if it was closed by a timeout, for example.
"""
function close!(server::Server, path::String)
    try
        borrow_file!(server, path) do file
            if file.timeout_timer !== nothing
                close(file.timeout_timer)
            end
            WorkerIPC.stop(file.worker)
            lock(server.lock) do
                pop!(server.workers, file.path)
                _gc_cache_files(joinpath(dirname(path), ".cache"))
                on_change(server)
            end
            GC.gc()
        end
        return true
    catch err
        if err isa FileBusyError
            throw(
                UserError(
                    "Tried to close file \"$path\" but the corresponding worker is busy.",
                ),
            )
        elseif !(err isa NoFileEntryError)
            rethrow(err)
        else
            false
        end
    end
end

function forceclose!(server::Server, path::String)
    apath = abspath(path)
    file = lock(server.lock) do
        if haskey(server.workers, apath)
            return server.workers[apath]
        else
            throw(NoFileEntryError(apath))
        end
    end
    # if the worker is not actually running we need to fall back to normal closing,
    # for that we try to get the file lock now
    lock_attained = trylock(file.lock)
    try
        # if we've attained the lock, we can close normally
        if lock_attained
            close!(server, path)
        else
            # Signal to run! that we're force-closing, then directly stop the worker.
            # This avoids a race where run! might consume :evaluate_finished first.
            put!(file.run_decision_channel, :forceclose)
            WorkerIPC.stop(file.worker)
        end
    finally
        lock_attained && unlock(file.lock)
    end
    return
end

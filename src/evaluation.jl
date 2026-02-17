# Notebook evaluation pipeline: parsing chunks, sending to workers, formatting outputs.

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

# The version of `julia` for a particular notebook file might not be the same
# as the runner process, so query the worker for this value.
function _get_julia_version(f::File)
    cmd = `$(f.exe) --version`
    return last(split(readchomp(cmd)))
end

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

        Logging.@debug "evaluate!" path chunks = length(raw_chunks)
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
            Logging.@debug "Cache hit, reusing cell outputs" path
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
                    if !contains(new_raw_chunk.source, INLINE_CODE_PATTERN)
                        # Swap out any markdown chunks with their updated content.
                        new_source = process_cell_source(new_raw_chunk.source)
                        empty!(output_chunk.source)
                        append!(output_chunk.source, new_source)
                    end
                end
            end
            cells = f.output_chunks
        else
            Logging.@debug "Evaluating cells" path
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
    record_error!(kind, file, traceback) = push!(error_metadata, (; kind, file, traceback))
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
                _evaluate_code_cell!(
                    cells,
                    f,
                    chunk,
                    nth,
                    allow_error_global,
                    record_error!,
                )
            end
        elseif chunk.type === :markdown
            _evaluate_markdown_cell!(cells, f, chunk, nth, record_error!)
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

    WorkerIPC.call(
        f.worker,
        WorkerIPC.EvaluateParamsRequest(file = f.path, params = params),
    )
    return
end

# Code cell evaluation: send to worker, format outputs, handle cell expansion.

"""
    _add_language_prefix_cell!(cells, chunk, nth, mth, expand_cell, language, fenced=false)

Add a markdown cell containing a fenced code block for displaying R/Python source.
When `fenced=true`, uses `{{language}}` syntax so fence markers are visible in output.
"""
function _add_language_prefix_cell!(
    cells,
    chunk,
    nth,
    mth,
    expand_cell,
    language::Symbol,
    fenced::Bool = false,
)
    lang_str = fenced ? "{{$(language)}}" : string(language)
    code = chomp(strip_cell_options(chunk.source))
    push!(
        cells,
        (;
            id = string(expand_cell ? string(nth, "_", mth) : string(nth), "_code_prefix"),
            cell_type = :markdown,
            metadata = (;),
            source = process_cell_source("```$(lang_str)\n$(code)\n```\n", Dict()),
        ),
    )
end

"""
    _get_user_echo(cell_options, chunk)

Get user's echo option for foreign (Python/R) cells.
Returns the echo value from cell_options if present, otherwise extracts from source.
"""
function _get_user_echo(cell_options, chunk)
    if haskey(cell_options, "echo")
        cell_options["echo"]
    else
        opts = extract_cell_options(chunk.source; file = chunk.file, line = chunk.line)
        get(opts, "echo", true)
    end
end

"""
    _evaluate_code_cell!(cells, f, chunk, nth, allow_error_global, record_error!)

Evaluate a single code cell: send to worker, handle expansion, format outputs.
"""
function _evaluate_code_cell!(cells, f, chunk, nth, allow_error_global, record_error!)
    Logging.@debug "Evaluating cell" file = chunk.file line = chunk.line
    source = transform_source(chunk)

    # Offset the line number by 1 to account for the triple backticks
    # that are part of the markdown syntax for code blocks.
    render_response = WorkerIPC.call(
        f.worker,
        WorkerIPC.RenderRequest(
            code = source,
            file = chunk.file,
            notebook = f.path,
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
        allow_error_cell = get(remote.cell_options, "error", allow_error_global)
        outputs = _format_worker_outputs(remote, allow_error_cell, record_error!, chunk)

        cell_options = expand_cell ? remote.cell_options : Dict()

        # Non-Julia code cells need a prefix cell with formatted source
        # since the notebook language is julia. Hide the actual code cell.
        if chunk.language in (:python, :r)
            user_echo = _get_user_echo(cell_options, chunk)
            if user_echo != false
                _add_language_prefix_cell!(
                    cells,
                    chunk,
                    nth,
                    mth,
                    expand_cell,
                    chunk.language,
                    user_echo == "fenced",
                )
            end
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

"""
    _format_worker_outputs(remote, allow_error_cell, record_error!, chunk)

Build the outputs vector for a single worker result cell. Handles display results,
execute results, evaluation errors, stdout, and show errors.
"""
function _format_worker_outputs(remote, allow_error_cell, record_error!, chunk)
    outputs = []
    processed = process_results(remote.results)

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
                        record_error!(
                            :show,
                            "$(chunk.file):$(chunk.line)",
                            join(each_error.traceback, "\n"),
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
        # Errors from evaluation of the code cell contents, not from `show`.
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
            record_error!(
                :cell,
                "$(chunk.file):$(chunk.line)",
                join(remote.backtrace, "\n"),
            )
        end
    end

    if !isempty(remote.output)
        pushfirst!(
            outputs,
            (; output_type = "stream", name = "stdout", text = remote.output),
        )
    end

    # Errors from the `show` output of values, not from cell evaluation.
    # If something throws here the user's `show` method has a bug.
    if !isempty(processed.errors)
        append!(outputs, processed.errors)
        if !allow_error_cell
            for each_error in processed.errors
                record_error!(
                    :show,
                    "$(chunk.file):$(chunk.line)",
                    join(each_error.traceback, "\n"),
                )
            end
        end
    end

    return outputs
end

# Markdown cell evaluation: inline code expansion.

"""
    _evaluate_markdown_cell!(cells, f, chunk, nth, record_error!)

Evaluate inline code in a markdown cell and push the result.
"""
function _evaluate_markdown_cell!(cells, f, chunk, nth, record_error!)
    marker = r"{(?:julia|python|r)} "
    source = chunk.source
    if contains(chunk.source, INLINE_CODE_PATTERN)
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
                            notebook = f.path,
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
                        record_error!(
                            :inline,
                            "inline: `$(node.literal)`",
                            join(remote.backtrace, "\n"),
                        )
                    else
                        processed = process_inline_results(remote.results)
                        source =
                            replace(source, "`$(node.literal)`" => "$processed"; count = 1)
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
end

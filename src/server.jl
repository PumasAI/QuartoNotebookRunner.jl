# Types.

mutable struct File
    worker::Malt.Worker
    path::String
    exeflags::Vector{String}
    env::Vector{String}
    lock::ReentrantLock

    function File(path::String, options::Union{String,Dict{String,Any}})
        if isfile(path)
            _, ext = splitext(path)
            if ext in (".jl", ".qmd")
                path = isabspath(path) ? path : abspath(path)

                options = _parsed_options(options)
                _, file_frontmatter = raw_text_chunks(path)
                merged_options = _extract_relevant_options(file_frontmatter, options)
                exeflags, env = _exeflags_and_env(merged_options)

                worker = cd(() -> Malt.Worker(; exeflags, env), dirname(path))
                file = new(worker, path, exeflags, env, ReentrantLock())
                init!(file)
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

function _exeflags_and_env(options)
    exeflags = map(String, options["format"]["metadata"]["julia"]["exeflags"])
    env = map(String, options["format"]["metadata"]["julia"]["env"])
    return exeflags, env
end

struct Server
    workers::Dict{String,File}
    lock::ReentrantLock # should be locked for mutation/lookup of the workers dict, not for evaling on the workers. use worker locks for that
    function Server()
        workers = Dict{String,File}()
        return new(workers, ReentrantLock())
    end
end

# Implementation.

function init!(file::File)
    worker = file.worker
    Malt.remote_eval_fetch(worker, worker_init(file))
end

function refresh!(file::File, options::Dict)
    exeflags, env = _exeflags_and_env(options)
    if exeflags != file.exeflags || env != file.env || !Malt.isrunning(file.worker) # the worker might have been killed on another task
        Malt.stop(file.worker)
        file.worker = cd(() -> Malt.Worker(; exeflags, env), dirname(file.path))
        file.exeflags = exeflags
        init!(file)
    end
    expr = :(refresh!($(options)))
    Malt.remote_eval_fetch(file.worker, expr)
end

"""
    evaluate!(f::File, [output])

Evaluate the code and markdown in `f` and return a vector of cells with the
results in all available mimetypes.

`output` can be a file path, or an IO stream.
"""
function evaluate!(
    f::File,
    output::Union{AbstractString,IO,Nothing} = nothing;
    showprogress = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
)
    _check_output_dst(output)

    options = _parsed_options(options)
    path = abspath(f.path)
    if isfile(path)
        raw_chunks, file_frontmatter = raw_text_chunks(f)
        merged_options = _extract_relevant_options(file_frontmatter, options)
        cells = evaluate_raw_cells!(f, raw_chunks, merged_options; showprogress)
        data = (
            metadata = (
                kernelspec = (
                    display_name = "Julia $(VERSION)",
                    language = "julia",
                    name = "julia-$(VERSION)",
                ),
                kernel_info = (name = "julia",),
                language_info = (
                    name = "julia",
                    version = VERSION,
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

function _extract_relevant_options(file_frontmatter::Dict, options::Dict)
    D = Dict{String,Any}

    file_frontmatter = _recursive_merge(default_frontmatter(), file_frontmatter)

    fig_width_default = get(file_frontmatter, "fig-width", nothing)
    fig_height_default = get(file_frontmatter, "fig-height", nothing)
    fig_format_default = get(file_frontmatter, "fig-format", nothing)
    fig_dpi_default = get(file_frontmatter, "fig-dpi", nothing)
    error_default = get(get(D, file_frontmatter, "execute"), "error", true)

    pandoc_to_default = nothing

    julia_default = get(file_frontmatter, "julia", nothing)

    if isempty(options)
        return _options_template(;
            fig_width = fig_width_default,
            fig_height = fig_height_default,
            fig_format = fig_format_default,
            fig_dpi = fig_dpi_default,
            error = error_default,
            pandoc_to = pandoc_to_default,
            julia = julia_default,
        )
    else
        format = get(D, options, "format")
        execute = get(D, format, "execute")
        fig_width = get(execute, "fig-width", fig_width_default)
        fig_height = get(execute, "fig-height", fig_height_default)
        fig_format = get(execute, "fig-format", fig_format_default)
        fig_dpi = get(execute, "fig-dpi", fig_dpi_default)
        error = get(execute, "error", error_default)

        pandoc = get(D, format, "pandoc")
        pandoc_to = get(pandoc, "to", pandoc_to_default)

        metadata = get(D, format, "metadata")
        julia = get(metadata, "julia", Dict())
        julia_merged = _recursive_merge(julia_default, julia)


        return _options_template(;
            fig_width,
            fig_height,
            fig_format,
            fig_dpi,
            error,
            pandoc_to,
            julia = julia_merged,
        )
    end
end

function _options_template(;
    fig_width,
    fig_height,
    fig_format,
    fig_dpi,
    error,
    pandoc_to,
    julia,
)
    D = Dict{String,Any}
    return D(
        "format" => D(
            "execute" => D(
                "fig-width" => fig_width,
                "fig-height" => fig_height,
                "fig-format" => fig_format,
                "fig-dpi" => fig_dpi,
                "error" => error,
            ),
            "pandoc" => D("to" => pandoc_to),
            "metadata" => D("julia" => julia),
        ),
    )
end

function _parsed_options(options::String)
    isfile(options) || error("`options` is not a valid file: $(repr(options))")
    open(options) do io
        return JSON3.read(io, Any)
    end
end
_parsed_options(options::Dict{String,Any}) = options

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

"""
    raw_text_chunks(file::File)

Return a vector of raw markdown and code chunks from `file` ready for evaluation
by `evaluate_raw_cells!`.
"""
raw_text_chunks(file::File) = raw_text_chunks(file.path)

function raw_text_chunks(path::String)
    endswith(path, ".qmd") && return raw_markdown_chunks(path)
    endswith(path, ".jl") && return raw_script_chunks(path)
    throw(ArgumentError("file is not a julia script or quarto markdown file: $(path)"))
end

"""
    raw_markdown_chunks(file::File)

Return a vector of raw markdown and code chunks from `file` ready
for evaluation by `evaluate_raw_cells!`.
"""
raw_markdown_chunks(file::File) = raw_markdown_chunks(file.path)

function raw_markdown_chunks(path::String)
    if !endswith(path, ".qmd")
        throw(ArgumentError("file is not a quarto markdown file: $(path)"))
    end

    if isfile(path)
        raw_chunks = []
        ast = open(Parser(), path)
        source_lines = readlines(path)
        terminal_line = 1
        code_cells = false
        for (node, enter) in ast
            if enter && is_julia_toplevel(node)
                code_cells = true
                line = node.sourcepos[1][1]
                markdown = join(source_lines[terminal_line:(line-1)], "\n")
                push!(
                    raw_chunks,
                    (
                        type = :markdown,
                        source = markdown,
                        file = path,
                        line = terminal_line,
                    ),
                )
                terminal_line = node.sourcepos[2][1] + 1

                # currently, the only execution-relevant cell option is `eval` which controls if a code block is executed or not.
                # this option could in the future also include a vector of line numbers, which knitr supports.
                # all other options seem to be quarto-rendering related, like where to put figure captions etc.
                source = node.literal
                cell_options = extract_cell_options(source; file = path, line = line)
                evaluate = get(cell_options, "eval", true)
                if !(evaluate isa Bool)
                    error(
                        "Cannot handle an `eval` code cell option with value $(repr(evaluate)), only true or false.",
                    )
                end
                push!(
                    raw_chunks,
                    (type = :code, source, file = path, line, evaluate, cell_options),
                )
            end
        end
        if terminal_line <= length(source_lines)
            markdown = join(source_lines[terminal_line:end], "\n")
            push!(
                raw_chunks,
                (type = :markdown, source = markdown, file = path, line = terminal_line),
            )
        end

        # The case where the notebook has no code cells.
        if isempty(raw_chunks) && !code_cells
            push!(
                raw_chunks,
                (type = :markdown, source = read(path, String), file = path, line = 1),
            )
        end

        frontmatter = _recursive_merge(default_frontmatter(), CommonMark.frontmatter(ast))

        return raw_chunks, frontmatter
    else
        throw(ArgumentError("file does not exist: $(path)"))
    end
end

_recursive_merge(x::AbstractDict...) = merge(_recursive_merge, x...)
_recursive_merge(x...) = x[end]

"""
    raw_script_chunks(file::File)

Return a vector of raw script chunks from `file` ready for evaluation by
`evaluate_raw_cells!`.

This function takes a `.jl` file containing `# %%` marker comments and splits
it into chunks of code and markdown. The markdown chunks are marked with
`# %% [markdown]` while the code chunks are marked with plain `# %%`. Markdown
content can either be multiline string literals, or comments. Code chunks can
contain cell attributes `#| {key: value}` which are parsed as YAML and passed
to the `render` function.
"""
raw_script_chunks(file::File) = raw_script_chunks(file.path)

function raw_script_chunks(path::String)
    if !endswith(path, ".jl")
        throw(ArgumentError("file is not a julia script file: $(path)"))
    end

    if isfile(path)
        lines = String[]
        cell_markers = Tuple{Int,Symbol}[]

        code_marker = r"^# %%$"
        markdown_marker = r"^# %% \[markdown\]$"

        for (nth, line) in enumerate(readlines(path; keep = true))
            push!(lines, line)
            line = rstrip(line)
            m = match(code_marker, line)
            if isnothing(m)
                m = match(markdown_marker, line)
                if isnothing(m)
                    if isempty(cell_markers)
                        error("first line of script must be a cell marker.")
                    end
                else
                    push!(cell_markers, (nth, :markdown))
                end
            else
                push!(cell_markers, (nth, :code))
            end
        end

        if isempty(cell_markers)
            error("script must contain at least one cell marker.")
        end

        push!(cell_markers, (length(lines) + 1, :unknown))

        raw_chunks = []

        frontmatter = Dict{String,Any}()

        for (nth, ((this_cell, type), (next_cell, _))) in
            enumerate(IterTools.partition(cell_markers, 2, 1))
            if type === :unknown
                error("last cell marker must be a code or markdown marker.")
            end

            start_line = clamp(this_cell + 1, 1, length(lines))
            end_line = clamp(next_cell - 1, 1, length(lines))

            source_lines = lines[start_line:end_line]
            source = join(source_lines)
            if type == :code

                cell_options = extract_cell_options(source; file = path, line = start_line)
                evaluate = get(cell_options, "eval", true)
                if !(evaluate isa Bool)
                    error(
                        "Cannot handle an `eval` code cell option with value $(repr(evaluate)), only true or false.",
                    )
                end
                push!(
                    raw_chunks,
                    (;
                        type = :code,
                        source,
                        file = path,
                        line = start_line,
                        evaluate,
                        cell_options,
                    ),
                )
            elseif type == :markdown
                try
                    text = Meta.parse(source)
                    if isa(text, AbstractString)
                        if nth == 1
                            frontmatter = CommonMark.frontmatter(Parser()(text))
                        end
                        push!(
                            raw_chunks,
                            (
                                type = :markdown,
                                source = text,
                                file = path,
                                line = start_line,
                            ),
                        )
                    else
                        filtered_lines = map(filter(startswith("#"), source_lines)) do line
                            _, rest = split(line, "#"; limit = 2)
                            if startswith(rest, " ")
                                _, rest = split(rest, " "; limit = 2)
                            end
                            return rest
                        end
                        text = join(filtered_lines)
                        if nth == 1
                            frontmatter = CommonMark.frontmatter(Parser()(text))
                        end
                        push!(
                            raw_chunks,
                            (
                                type = :markdown,
                                source = text,
                                file = path,
                                line = start_line,
                            ),
                        )
                    end
                catch error
                    isa(error, Meta.ParseError) || rethrow()
                    error("invalid markdown block content")
                end
            else
                error("unreachable reached.")
            end
        end

        frontmatter = _recursive_merge(frontmatter, default_frontmatter())

        return raw_chunks, frontmatter
    else
        throw(ArgumentError("file does not exist: $(path)"))
    end
end

function default_frontmatter()
    D = Dict{String,Any}
    exeflags = JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_EXEFLAGS", "[]"), Vector{String})
    env = JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_ENV", "[]"), Vector{String})
    return D(
        "fig-format" => "png",
        "julia" => D("exeflags" => exeflags, "env" => env),
        "execute" => D("error" => true),
    )
end

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

"""
    evaluate_raw_cells!(f::File, chunks::Vector)

Evaluate the raw cells in `chunks` and return a vector of cells with the results
in all available mimetypes.
"""
function evaluate_raw_cells!(f::File, chunks::Vector, options::Dict; showprogress = true)
    refresh!(f, options)
    cells = []

    has_error = false
    allow_error_global = options["format"]["execute"]["error"]

    header = "Running $(relpath(f.path, pwd()))"
    @maybe_progress showprogress "$header" for (nth, chunk) in enumerate(chunks)
        if chunk.type === :code

            outputs = []

            if chunk.evaluate
                # Offset the line number by 1 to account for the triple backticks
                # that are part of the markdown syntax for code blocks.
                expr = :(render(
                    $chunk.source,
                    $(chunk.file),
                    $(chunk.line + 1),
                    $(chunk.cell_options),
                ))
                remote = Malt.remote_eval_fetch(f.worker, expr)
                processed = process_results(remote.results)

                # Should this notebook cell be allowed to throw an error? When
                # not allowed, we log all errors don't generate an output.
                allow_error_cell = get(chunk.cell_options, "error", allow_error_global)

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
                                    traceback = Text(join(each_error.traceback, "\n"))
                                    @error "stopping notebook evaluation due to unexpected `show` error." file traceback
                                    has_error = true
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
                        traceback = Text(join(remote.backtrace, "\n"))
                        @error "stopping notebook evaluation due to unexpected cell error." file traceback
                        has_error = true
                    end
                end

                if !isempty(remote.output)
                    pushfirst!(
                        outputs,
                        (; output_type = "stream", name = "stdout", text = remote.output),
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
                            traceback = Text(join(each_error.traceback, "\n"))
                            @error "stopping notebook evaluation due to unexpected `show` error." file traceback
                            has_error = true
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
                    source = process_cell_source(chunk.source),
                    outputs,
                    execution_count = chunk.evaluate ? 1 : 0,
                ),
            )
        elseif chunk.type === :markdown
            marker = "{julia} "
            source = chunk.source
            if contains(chunk.source, "`$marker")
                parser = Parser()
                for (node, enter) in parser(chunk.source)
                    if enter && node.t isa CommonMark.Code
                        if startswith(node.literal, marker)
                            source_code = replace(node.literal, marker => "")
                            expr = :(render($(source_code), $(chunk.file), $(chunk.line)))
                            remote = Malt.remote_eval_fetch(f.worker, expr)
                            if !isnothing(remote.error)
                                error("Error rendering inline code: $(remote.error)")
                            end
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
    if has_error
        error("Unexpected cell errors, see logs above.")
    end

    return cells
end

# All but the last line of a cell should contain a newline character to end it.
function process_cell_source(source::AbstractString)
    lines = collect(eachline(IOBuffer(source); keep = true))
    if isempty(lines)
        return []
    else
        lines[end] = rstrip(lines[end])
        return lines
    end
end

function extract_cell_options(source::AbstractString; file::AbstractString, line::Integer)
    prefix = "#| "
    yaml = IOBuffer()
    none = true
    for line in eachline(IOBuffer(source))
        if startswith(line, prefix)
            _, rest = split(line, prefix; limit = 2)
            println(yaml, rest)
            none = false
        end
    end
    if none
        return Dict{String,Any}()
    else
        seekstart(yaml)
        options = try
            YAML.load(yaml)
        catch
            msg = """
                  Error parsing cell attributes at $(file):$(line):

                  ```{julia}
                  $source
                  ```
                  """
            error(msg)
        end
        isa(options, Dict) || error("Cell attributes must be a dictionary.")
        return options
    end
end

function process_inline_results(dict::Dict)
    # A reduced set of mimetypes are available for inline use.
    for (mime, func) in ["text/markdown" => String, "text/plain" => _escape_markdown]
        if haskey(dict, mime)
            payload = dict[mime]
            if payload.error
                error("Error rendering inline code: $(String(payload.data))")
            else
                return func(payload.data)
            end
        end
    end
    error("No valid mimetypes found in inline code results.")
end

_escape_markdown(s::AbstractString) = replace(s, r"([\\`*_{}[\]()#+\-.!|])" => s"\\\1")
_escape_markdown(bytes::Vector{UInt8}) = _escape_markdown(String(bytes))

"""
    process_results(dict::Dict{String,Vector{UInt8}})

Process the results of a remote evaluation into a dictionary of mimetypes to
values. We do here rather than in the worker because we don't want to have to
define additional functions in the worker and import `Base64` there. The worker
just has to provide bytes.
"""
function process_results(dict::Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}})
    funcs = Dict(
        "application/json" => json_reader,
        "text/plain" => String,
        "text/markdown" => String,
        "text/html" => String,
        "text/latex" => String,
        "image/svg+xml" => String,
        "image/png" => Base64.base64encode,
    )
    meta_funcs = Dict("image/png" => png_image_metadata)

    data = Dict{String,Any}()
    metadata = Dict{String,Any}()
    errors = []

    for (mime, payload) in dict
        if payload.error
            traceback = collect(eachline(IOBuffer(payload.data)))
            push!(
                errors,
                (;
                    output_type = "error",
                    ename = "$mime showerror",
                    evalue = "$mime showerror",
                    traceback,
                ),
            )
        else
            bytes = payload.data
            # Don't include outputs if the result is `nothing`.
            d = get(funcs, mime, Compat.Returns(nothing))(bytes)
            isnothing(d) || (data[mime] = d)
            m = get(meta_funcs, mime, Compat.Returns(nothing))(bytes)
            isnothing(m) || (metadata[mime] = m)
        end
    end

    return (; data, metadata, errors)
end

function png_image_metadata(bytes::Vector{UInt8})
    io = IOBuffer(bytes)
    seekstart(io)
    png = PNGFiles.load(io)
    height, width = size(png)
    return (; width, height)
end

"""
    is_julia_toplevel(node::CommonMark.Node)

Return `true` if `node` is a Julia toplevel code block.
"""
is_julia_toplevel(node) =
    node.t isa CommonMark.CodeBlock &&
    node.t.info == "{julia}" &&
    node.parent.t isa CommonMark.Document

function run!(
    server::Server,
    path::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    showprogress::Bool = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
)
    borrow_file!(server, path; optionally_create = true) do file
        return evaluate!(file, output; showprogress, options)
    end
end

struct NoFileEntryError <: Exception
    path::String
end

"""
    borrow_file!(f, server, path; optionally_create = false, options = Dict{String,Any}())

Executes `f(file)` while the `file`'s `ReentrantLock` is locked.
All actions on a `Server`'s `File` should be wrapped in this
so that no two tasks can mutate the `File` at the same time.
When `optionally_create` is `true`, the `File` will be created on the server
if it doesn't exist, in which case it is passed `options`.
"""
function borrow_file!(
    f,
    server,
    path;
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
        lock(file.lock) do
            current_file = lock(server.lock) do
                get(server.workers, apath, nothing)
            end
            if file !== current_file
                return borrow_file!(f, server, apath; optionally_create)
            else
                return f(file)
            end
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

function close!(server::Server, path::String)
    borrow_file!(server, path) do file
        Malt.stop(file.worker)
        lock(server.lock) do
            delete!(server.workers, path)
        end
        GC.gc()
    end
end

json_reader(str) = JSON3.read(str, Any)
yaml_reader(str) = YAML.load(str)

function Parser()
    parser = CommonMark.Parser()
    CommonMark.enable!(parser, CommonMark.FrontMatterRule(; yaml = yaml_reader))
    return parser
end

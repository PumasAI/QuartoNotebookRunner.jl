# Types.

mutable struct File
    worker::Malt.Worker
    path::String
    exeflags::Vector{String}

    function File(path::String)
        if isfile(path)
            _, ext = splitext(path)
            if ext in (".jl", ".qmd")
                path = isabspath(path) ? path : abspath(path)

                _, frontmatter = raw_text_chunks(path)
                exeflags = frontmatter["julia"]["exeflags"]

                worker = cd(() -> Malt.Worker(; exeflags), dirname(path))
                file = new(worker, path, exeflags)
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

struct Server
    workers::Dict{String,File}

    function Server()
        workers = Dict{String,File}()
        return new(workers)
    end
end

# Implementation.

function init!(file::File)
    worker = file.worker
    Malt.remote_eval_fetch(worker, worker_init(file))
end

function refresh!(file::File, frontmatter::Dict)
    exeflags = frontmatter["julia"]["exeflags"]
    if exeflags != file.exeflags
        Malt.stop(file.worker)
        file.worker = cd(() -> Malt.Worker(; exeflags), dirname(file.path))
        file.exeflags = exeflags
        init!(file)
    end
    expr = :(refresh!($(frontmatter)))
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
)
    _check_output_dst(output)

    path = abspath(f.path)
    if isfile(path)
        raw_chunks, frontmatter = raw_text_chunks(f)
        cells = evaluate_raw_cells!(f, raw_chunks, frontmatter; showprogress)
        data = (
            metadata = (
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
                push!(raw_chunks, (type = :code, source, file = path, line, evaluate))
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
_recursive_merge(x::AbstractVector...) = cat(x...; dims = 1)
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
                    (type = :code, source, file = path, line = start_line, evaluate),
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
    Dict{String,Any}("fig-format" => "png", "julia" => Dict{String,Any}("exeflags" => []))
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
function evaluate_raw_cells!(
    f::File,
    chunks::Vector,
    frontmatter::Dict;
    showprogress = true,
)
    refresh!(f, frontmatter)
    cells = []
    @maybe_progress showprogress "Running $(relpath(f.path, pwd()))" for (nth, chunk) in
                                                                         enumerate(chunks)
        if chunk.type === :code

            outputs = []

            if chunk.evaluate
                # Offset the line number by 1 to account for the triple backticks
                # that are part of the markdown syntax for code blocks.
                expr = :(render($chunk.source, $(chunk.file), $(chunk.line + 1)))
                remote = Malt.remote_eval_fetch(f.worker, expr)
                processed = process_results(remote.results)

                if isnothing(remote.error)
                    push!(
                        outputs,
                        (;
                            output_type = "execute_result",
                            execution_count = 1,
                            processed.data,
                            processed.metadata,
                        ),
                    )
                else
                    push!(
                        outputs,
                        (;
                            output_type = "error",
                            ename = remote.error,
                            evalue = get(processed.data, "text/plain", ""),
                            traceback = remote.backtrace,
                        ),
                    )
                end

                if !isempty(remote.output)
                    pushfirst!(
                        outputs,
                        (; output_type = "stream", name = "stdout", text = remote.output),
                    )
                end

                if !isempty(processed.errors)
                    append!(outputs, processed.errors)
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
            push!(
                cells,
                (;
                    id = string(nth),
                    cell_type = chunk.type,
                    metadata = (;),
                    source = process_cell_source(chunk.source),
                ),
            )
        else
            throw(ArgumentError("unknown chunk type: $(chunk.type)"))
        end
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
    function error_message(io::IO, msg::AbstractString)
        print(io, " ")
        printstyled(IOContext(io, :color => true), "← $msg"; color = :red, bold = true)
    end

    prefix = "#| "
    options = Dict{String,Any}()

    msg = IOBuffer()
    errors = false

    for line in eachline(IOBuffer(source))
        print(msg, line)
        if startswith(line, prefix)
            _, rest = split(line, prefix; limit = 2)
            rest = lstrip(rest)
            if isempty(rest)
                error_message(msg, "blank line")
                errors = true
            else
                try
                    option = YAML.load(rest)
                    if isa(option, Dict)
                        merge!(options, option)
                    else
                        error_message(msg, "invalid syntax")
                        errors = true
                    end
                catch error
                    error_message(msg, string(error))
                    errors = true
                end
            end
        end
        println(msg)
    end
    if errors
        error("""
        Error parsing cell attributes:

        $(file):$(line)
        ```{julia}
        $(rstrip(String(take!(msg))))
        ```
        """)
    end
    return options
end

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

function loadfile!(server::Server, path::String)
    file = File(path)
    server.workers[path] = file
    return file
end

function run!(
    server::Server,
    file::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    showprogress::Bool = true,
)
    file = get!(server.workers, file) do
        @debug "file not loaded, loading first." file
        loadfile!(server, file)
    end
    return evaluate!(file, output; showprogress)
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
    for path in keys(server.workers)
        close!(server, path)
    end
end

function close!(server::Server, path::String)
    Malt.stop(server.workers[path].worker)
    delete!(server.workers, path)
    GC.gc()
end

json_reader(str) = JSON3.read(str, Any)
yaml_reader(str) = YAML.load(str)

function Parser()
    parser = CommonMark.Parser()
    CommonMark.enable!(parser, CommonMark.FrontMatterRule(; yaml = yaml_reader))
    return parser
end

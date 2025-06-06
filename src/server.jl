# Types.

mutable struct File
    worker::Malt.Worker
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
                exeflags, env = _exeflags_and_env(merged_options)
                timeout = _extract_timeout(merged_options)


                exe, _exeflags = _julia_exe(exeflags)
                worker =
                    cd(() -> Malt.Worker(; exe, exeflags = _exeflags, env), dirname(path))
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
                    Channel{Symbol}(32), # we don't want an unbuffered channel because we might want to `put!` to it without blocking
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

function _has_juliaup()
    try
        success(`juliaup --version`) && success(`julia --version`)
    catch error
        return false
    end
end

function _julia_exe(exeflags)
    # Find the `julia` executable to use for this worker process. If the
    # `juliaup` command is available, we can use plain `julia` if a channel has
    # been provided in the exeflags. The channel exeflag is dropped from the
    # exeflags vector so that it isn't provided twice, the second of which
    # would be treated as a file name.
    if _has_juliaup()
        indices = findall(startswith("+"), exeflags)
        if isempty(indices)
            quarto_julia = get(ENV, "QUARTO_JULIA", nothing)
            if isnothing(quarto_julia)
                # Use the default `julia` channel set for `juliaup`.
                return `julia`, exeflags
            else
                # Use the `julia` binary that was specified in the environment
                # variable that can be passed to `quarto` to pick the server
                # process `julia` to use.
                return `$quarto_julia`, exeflags
            end
        else
            # Pull out the channel from the exeflags. Since we merge in
            # exeflags from the `QUARTONOTEBOOKRUNNER_EXEFLAGS` environment
            # variable, we can't just drop the first element of the exeflags
            # since there may be more than one provided. Keep the last one.
            channel = exeflags[last(indices)]
            exeflags = exeflags[setdiff(1:end, indices)]
            return `julia $channel`, exeflags
        end
    end
    # Just use the current `julia` if there is no `juliaup` command available.
    bin = Base.julia_cmd()[1]
    return `$bin`, exeflags
end

function _extract_timeout(merged_options)
    daemon = merged_options["format"]["execute"]["daemon"]
    if daemon === true
        300.0 # match quarto's default timeout of 300 seconds
    elseif daemon === false
        0.0
    elseif daemon isa Real
        f = Float64(daemon)
        if f < 0
            throw(
                ArgumentError(
                    "Invalid execute.daemon value $f, must be a bool or a non-negative number (in seconds).",
                ),
            )
        end
        f
    else
        throw(
            ArgumentError(
                "Invalid execute.daemon value $daemon, must be a bool or a non-negative number (in seconds).",
            ),
        )
    end
end

function _exeflags_and_env(options)
    env_exeflags =
        JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_EXEFLAGS", "[]"), Vector{String})
    options_exeflags = map(String, options["format"]["metadata"]["julia"]["exeflags"])
    # We want to be able to override exeflags that are defined via environment variable,
    # but leave the remaining flags intact (for example override number of threads but leave sysimage).
    # We can do this by adding the options exeflags after the env exeflags.
    # Julia will ignore earlier uses of the same flag.
    exeflags = [env_exeflags; options_exeflags]
    env = map(String, options["format"]["metadata"]["julia"]["env"])
    # Use `--project=@.` if neither `JULIA_PROJECT=...` nor `--project=...` are specified
    if !any(startswith("JULIA_PROJECT="), env) && !any(startswith("--project="), exeflags)
        # Set it via the env variable since this is the "weakest" form of
        # setting it, which allows for an implicit `--project=` provided by a
        # custom linked `juliaup` channel to override it, e.g `julia
        # +CustomChannel` that is a link to `julia +channel --project=@global`.
        pushfirst!(env, "JULIA_PROJECT=@.")
    end
    # if exeflags already contains '--color=no', the 'no' will prevail
    pushfirst!(exeflags, "--color=yes")

    # Ensure that coverage settings are passed to the worker so that worker
    # code is tracked correctly during tests.
    # Based on https://github.com/JuliaLang/julia/blob/eed18bdf706b7aab15b12f3ba0588e8fafcd4930/base/util.jl#L216-L229.
    opts = Base.JLOptions()
    if opts.code_coverage != 0
        # Forward the code-coverage flag only if applicable (if the filename
        # is pid-dependent)
        coverage_file =
            (opts.output_code_coverage != C_NULL) ?
            unsafe_string(opts.output_code_coverage) : ""
        if isempty(coverage_file) || occursin("%p", coverage_file)
            if opts.code_coverage == 1
                push!(exeflags, "--code-coverage=user")
            elseif opts.code_coverage == 2
                push!(exeflags, "--code-coverage=all")
            elseif opts.code_coverage == 3
                push!(exeflags, "--code-coverage=@$(unsafe_string(opts.tracked_path))")
            end
            isempty(coverage_file) || push!(exeflags, "--code-coverage=$coverage_file")
        end
    end

    return exeflags, env
end

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

function remote_eval_fetch_channeled(worker, expr)
    code = quote
        put!(stable_execution_task_channel_in, $(QuoteNode(expr)))
        take!(stable_execution_task_channel_out)
    end
    return Malt.remote_eval_fetch(worker, code)
end

function init!(file::File, options::Dict)
    worker = file.worker
    Malt.remote_eval_fetch(worker, worker_init(file, options))
end

function refresh!(file::File, options::Dict)
    exeflags, env = _exeflags_and_env(options)
    if exeflags != file.exeflags || env != file.env || !Malt.isrunning(file.worker) # the worker might have been killed on another task
        Malt.stop(file.worker)
        exe, _exeflags = _julia_exe(exeflags)
        file.worker =
            cd(() -> Malt.Worker(; exe, exeflags = _exeflags, env), dirname(file.path))
        file.exe = exe
        file.exeflags = exeflags
        file.env = env
        file.source_code_hash = hash(VERSION)
        file.output_chunks = []
        init!(file, options)
    end
    remote_eval_fetch_channeled(file.worker, :(refresh!($(options)); revise_hook()))
end

function _cache_file(f::File, source_code_hash)
    path = joinpath(dirname(f.path), ".cache")
    hs = string(hash(f.worker.manifest_file, source_code_hash); base = 62)
    return joinpath(path, "$(basename(f.path)).$hs.json")
end

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
            for each in v[4:end]
                rm(each.file; force = true)
            end
        end
    end
end

const SCHEMA_VERSION = v"1.0.0"

function load_from_file!(f::File, source_code_hash)
    # Only load from file cache on initial load, not once the file is populated
    # with chunks.
    if isempty(f.output_chunks)
        file = _cache_file(f, source_code_hash)
        if isfile(file)
            try
                json = JSON3.read(file, @NamedTuple{cells::Vector{NamedTuple}})
                f.output_chunks = json.cells
                f.source_code_hash = source_code_hash
            catch error
                @debug "invalid cache file, skipping" error
            end
        end
        # Perform a garbage collection of the oldest cache files.
        _gc_cache_files(dirname(file))
    end
    return nothing
end

function save_to_file!(f::File)
    file = _cache_file(f, f.source_code_hash)
    dir = dirname(file)
    isdir(dir) || mkpath(dir)
    json = (;
        cells = f.output_chunks,
        timestamp = Dates.now(),
        file = f.path,
        qnr_schema_version = SCHEMA_VERSION,
    )
    write_json(file, json)
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
)
    _check_output_dst(output)

    options = _parsed_options(options)
    path = abspath(f.path)
    if isfile(path)
        source_code_hash, raw_chunks, file_frontmatter = raw_text_chunks(f, markdown)
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

function _extract_relevant_options(file_frontmatter::Dict, options::Dict)
    D = Dict{String,Any}

    file_frontmatter = _recursive_merge(default_frontmatter(), file_frontmatter)

    fig_width_default = get(file_frontmatter, "fig-width", nothing)
    fig_height_default = get(file_frontmatter, "fig-height", nothing)
    fig_format_default = get(file_frontmatter, "fig-format", nothing)
    fig_dpi_default = get(file_frontmatter, "fig-dpi", nothing)
    error_default = get(get(D, file_frontmatter, "execute"), "error", true)
    eval_default = get(get(D, file_frontmatter, "execute"), "eval", true)
    daemon_default = get(get(D, file_frontmatter, "execute"), "daemon", true)
    cache_default = get(get(D, file_frontmatter, "execute"), "cache", false)

    pandoc_to_default = nothing

    julia_default = get(file_frontmatter, "julia", nothing)

    params_default = get(file_frontmatter, "params", Dict{String,Any}())

    if isempty(options)
        return _options_template(;
            fig_width = fig_width_default,
            fig_height = fig_height_default,
            fig_format = fig_format_default,
            fig_dpi = fig_dpi_default,
            error = error_default,
            eval = eval_default,
            pandoc_to = pandoc_to_default,
            julia = julia_default,
            daemon = daemon_default,
            params = params_default,
            cache = cache_default,
        )
    else
        format = get(D, options, "format")
        execute = get(D, format, "execute")
        fig_width = get(execute, "fig-width", fig_width_default)
        fig_height = get(execute, "fig-height", fig_height_default)
        fig_format = get(execute, "fig-format", fig_format_default)
        fig_dpi = get(execute, "fig-dpi", fig_dpi_default)
        error = get(execute, "error", error_default)
        eval = get(execute, "eval", eval_default)
        daemon = get(execute, "daemon", daemon_default)
        cache = get(execute, "cache", cache_default)

        pandoc = get(D, format, "pandoc")
        pandoc_to = get(pandoc, "to", pandoc_to_default)

        metadata = get(D, format, "metadata")
        julia = get(metadata, "julia", Dict())
        julia_merged = _recursive_merge(julia_default, julia)

        # quarto stores params in two places currently, in `format.metadata.params` we have params specified in the front matter
        # and in top-level `params` we have the parameters via command-line arguments.
        # In case quarto decides to unify this behavior later, we probably can stop merging these on our side.
        # Cf. https://github.com/quarto-dev/quarto-cli/issues/9197
        params = get(metadata, "params", Dict())
        cli_params = get(options, "params", Dict())
        params_merged = _recursive_merge(params_default, params, cli_params)

        return _options_template(;
            fig_width,
            fig_height,
            fig_format,
            fig_dpi,
            error,
            eval,
            pandoc_to,
            julia = julia_merged,
            daemon,
            params = params_merged,
            cache,
        )
    end
end

function _options_template(;
    fig_width,
    fig_height,
    fig_format,
    fig_dpi,
    error,
    eval,
    pandoc_to,
    julia,
    daemon,
    params,
    cache,
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
                "eval" => eval,
                "daemon" => daemon,
                "cache" => cache,
            ),
            "pandoc" => D("to" => pandoc_to),
            "metadata" => D("julia" => julia),
        ),
        "params" => D(params),
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
raw_text_chunks(file::File, ::Nothing) = raw_text_chunks(file.path)
raw_text_chunks(file::File, markdown::String) =
    raw_markdown_chunks_from_string(file.path, markdown)

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
raw_markdown_chunks(file::File) =
    endswith(path, ".qmd") ? raw_markdown_chunks(file.path) :
    throw(ArgumentError("file is not a quarto markdown file: $(path)"))
raw_markdown_chunks(path::String) =
    raw_markdown_chunks_from_string(path, read(path, String))

struct Unset end

function raw_markdown_chunks_from_string(path::String, markdown::String)
    raw_chunks = []
    source_code_hash = hash(VERSION)
    pars = Parser()
    ast = pars(markdown; source = path)
    file_fromtmatter = CommonMark.frontmatter(ast)
    source_code_hash = hash(file_fromtmatter, source_code_hash)
    source_lines = collect(eachline(IOBuffer(markdown)))
    terminal_line = 1
    code_cells = false
    for (node, enter) in ast
        if enter &&
           (is_julia_toplevel(node) || is_python_toplevel(node) || is_r_toplevel(node))
            code_cells = true
            line = node.sourcepos[1][1]
            md = join(source_lines[terminal_line:(line-1)], "\n")
            push!(
                raw_chunks,
                (type = :markdown, source = md, file = path, line = terminal_line),
            )
            if contains(md, r"`{(?:julia|python|r)} ")
                source_code_hash = hash(md, source_code_hash)
            end
            terminal_line = node.sourcepos[2][1] + 1

            # currently, the only execution-relevant cell option is `eval` which controls if a code block is executed or not.
            # this option could in the future also include a vector of line numbers, which knitr supports.
            # all other options seem to be quarto-rendering related, like where to put figure captions etc.
            source = node.literal
            cell_options = extract_cell_options(source; file = path, line = line)
            evaluate = get(cell_options, "eval", Unset())
            if !(evaluate isa Union{Bool,Unset})
                error(
                    "Cannot handle an `eval` code cell option with value $(repr(evaluate)), only true or false.",
                )
            end
            language =
                is_julia_toplevel(node) ? :julia :
                is_python_toplevel(node) ? :python :
                is_r_toplevel(node) ? :r : error("Unhandled code block language")
            push!(
                raw_chunks,
                (
                    type = :code,
                    language = language,
                    source,
                    file = path,
                    line,
                    evaluate,
                    cell_options,
                ),
            )
            source_code_hash = hash(source, source_code_hash)
        end
    end
    if terminal_line <= length(source_lines)
        md = join(source_lines[terminal_line:end], "\n")
        push!(
            raw_chunks,
            (type = :markdown, source = md, file = path, line = terminal_line),
        )
        if contains(md, r"`{(?:julia|python|r)} ")
            source_code_hash = hash(md, source_code_hash)
        end
    end

    # The case where the notebook has no code cells.
    if isempty(raw_chunks) && !code_cells
        push!(raw_chunks, (type = :markdown, source = markdown, file = path, line = 1))
        if contains(markdown, r"`{(?:julia|python|r)} ")
            source_code_hash = hash(markdown, source_code_hash)
        end
    end

    # When there is a code block at the very end of the notebook we normalise
    # it by adding a blank markdown chunk afterwards. This allows the code that
    # tracks source code hashes and performs the chunk mutations that swap out
    # cached values to not have to worry about special casing whether there is
    # a code block or markdown at the end. This results in more straightforward
    # code there.
    if raw_chunks[end].type == :code
        push!(
            raw_chunks,
            (type = :markdown, source = "", file = path, line = terminal_line),
        )
    end

    frontmatter = _recursive_merge(default_frontmatter(), file_fromtmatter)

    return source_code_hash, raw_chunks, frontmatter
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
        source_code_hash = hash(VERSION)

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
                evaluate = get(cell_options, "eval", Unset())
                if !(evaluate isa Union{Bool,Unset})
                    error(
                        "Cannot handle an `eval` code cell option with value $(repr(evaluate)), only true or false.",
                    )
                end
                push!(
                    raw_chunks,
                    (;
                        type = :code,
                        language = :julia,
                        source,
                        file = path,
                        line = start_line,
                        evaluate,
                        cell_options,
                    ),
                )
                source_code_hash = hash(source, source_code_hash)
            elseif type == :markdown
                try
                    text = Meta.parse(rstrip(source))
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

        return source_code_hash, raw_chunks, frontmatter
    else
        throw(ArgumentError("file does not exist: $(path)"))
    end
end

function default_frontmatter()
    D = Dict{String,Any}
    env = JSON3.read(get(ENV, "QUARTONOTEBOOKRUNNER_ENV", "[]"), Vector{String})
    return D(
        "fig-format" => "png",
        "julia" => D("env" => env, "exeflags" => []),
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
                expr = :(render(
                    $source,
                    $(chunk.file),
                    $(chunk.line + 1),
                    $(chunk.cell_options),
                ))

                worker_results, expand_cell = remote_eval_fetch_channeled(f.worker, expr)

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
                            expr = :(render(
                                $(source_code),
                                $(chunk.file),
                                $(chunk.line);
                                inline = true,
                            ))
                            # There should only ever be a single result from an
                            # inline evaluation since you can't pass cell
                            # options and so `expand` will always be `false`.
                            worker_results, expand_cell =
                                remote_eval_fetch_channeled(f.worker, expr)
                            expand_cell && error("inline code cells cannot be expanded")
                            remote = only(worker_results)
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

    exprs = map(collect(pairs(params))) do (key, value)
        :(@eval getfield(Main, :Notebook) const $(Symbol(key::String)) = $value)
    end
    expr = Expr(:block, exprs...)
    remote_eval_fetch_channeled(f.worker, expr)
    return
end

# All but the last line of a cell should contain a newline character to end it.
# The optional `cell_options` argument is a dictionary of cell attributes which
# are written into the processed cell source when the cell is the result of an
# expansion of an `expand` cell.
function process_cell_source(source::AbstractString, cell_options::Dict = Dict())
    lines = collect(eachline(IOBuffer(source); keep = true))
    if !isempty(lines)
        lines[end] = rstrip(lines[end])
    end
    if isempty(cell_options)
        return lines
    else
        yaml = YAML.write(cell_options)
        return vcat(
            String["#| $line" for line in eachline(IOBuffer(yaml); keep = true)],
            lines,
        )
    end
end

function strip_cell_options(source::AbstractString)
    lines = collect(eachline(IOBuffer(source); keep = true))
    keep_from = something(findfirst(lines) do line
        !startswith(line, "#|")
    end, 1)
    join(lines[keep_from:end])
end

function wrap_with_r_boilerplate(code)
    """
    @isdefined(RCall) && RCall isa Module && Base.PkgId(RCall).uuid == Base.UUID("6f49c342-dc21-5d91-9882-a32aef131414") || error("RCall must be imported to execute R code cells with QuartoNotebookRunner")
    RCall.rcopy(RCall.R\"\"\"
    $code
    \"\"\")
    """
end

function wrap_with_python_boilerplate(code)
    """
    Main.QuartoNotebookWorker.py\"\"\"
    $code
    \"\"\"
    """
end

function transform_source(chunk)
    if chunk.language === :julia
        chunk.source
    elseif chunk.language === :r
        wrap_with_r_boilerplate(chunk.source)
    elseif chunk.language === :python
        wrap_with_python_boilerplate(chunk.source)
    else
        error("Unhandled code chunk language $(chunk.language)")
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
        if !isa(options, Dict)
            msg = """
                  Invalid cell attributes type at $(file):$(line):

                  ```{julia}
                  $source
                  ```

                  Expected a dictionary, got $(typeof(options)). Check for
                  syntax errors in the YAML block at the start of this cell.
                  """
            error(msg)
        end
        return options
    end
end

function process_inline_results(dict::Dict)
    isempty(dict) && return ""
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
        "application/pdf" => Base64.base64encode,
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

function png_image_metadata(bytes::Vector{UInt8}; phys_correction = true)
    if @view(bytes[1:8]) != b"\x89PNG\r\n\x1a\n"
        throw(ArgumentError("Not a png file"))
    end

    chunk_start::Int = 9

    _load(T, bytes, index) = ntoh(reinterpret(T, @view(bytes[index:index+sizeof(T)-1]))[])

    function read_chunk!()
        chunk_start > lastindex(bytes) && return nothing
        chunk_data_length = _load(UInt32, bytes, chunk_start)
        type = @view(bytes[chunk_start+4:chunk_start+7])
        data = @view(bytes[chunk_start+8:chunk_start+8+chunk_data_length-1])
        result = (; chunk_start, type, data)

        # advance the chunk_start state variable
        chunk_start += 4 + 4 + chunk_data_length + 4 # length, type, data, crc

        return result
    end

    chunk = read_chunk!()
    if chunk === nothing
        error("PNG file had no chunks")
    end
    if chunk.type != b"IHDR"
        error("PNG file must start with IHDR chunk, started with $(chunk.type)")
    end

    width = Int(_load(UInt32, chunk.data, 1))
    height = Int(_load(UInt32, chunk.data, 5))

    if phys_correction
        # if the png reports a physical pixel size, i.e., it has a pHYs chunk
        # with the pixels per meter unit flag set, correct the basic width and height
        # by those physical pixel sizes so that quarto receives the intended size
        # in CSS pixels
        while true
            chunk = read_chunk!()
            chunk === nothing && break
            chunk.type == b"IDAT" && break
            if chunk.type == b"pHYs"
                is_in_meters = Bool(_load(UInt8, chunk.data, 9))
                is_in_meters || break
                x_px_per_meter = _load(UInt32, chunk.data, 1)
                y_px_per_meter = _load(UInt32, chunk.data, 5)
                # it seems sensible to round the final image size to full CSS pixels,
                # especially given that png doesn't store dpi but px per meter
                # in an integer format, losing some precision
                width = round(Int, width / x_px_per_meter * (96 / 0.0254))
                height = round(Int, height / y_px_per_meter * (96 / 0.0254))
                break
            end
        end
    end

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

is_python_toplevel(node) =
    node.t isa CommonMark.CodeBlock &&
    node.t.info == "{python}" &&
    node.parent.t isa CommonMark.Document

is_r_toplevel(node) =
    node.t isa CommonMark.CodeBlock &&
    node.t.info == "{r}" &&
    node.parent.t isa CommonMark.Document

function run!(
    server::Server,
    path::AbstractString;
    output::Union{AbstractString,IO,Nothing} = nothing,
    markdown::Union{Nothing,String} = nothing,
    showprogress::Bool = true,
    options::Union{String,Dict{String,Any}} = Dict{String,Any}(),
    chunk_callback = (i, n, c) -> nothing,
)
    try
        borrow_file!(server, path; optionally_create = true) do file
            if file.timeout_timer !== nothing
                close(file.timeout_timer)
                file.timeout_timer = nothing
            end
            file.run_started = Dates.now()
            file.run_finished = nothing

            # we want to be able to force close the worker while `evaluate!` is running,
            # so we run `evaluate!` in a task and wait for the `run_decision_channel`
            # further down. Depending on the value fetched from that channel, we either
            # know that evaluation has finished, or that force closing was requested.
            while !isempty(file.run_decision_channel)
                take!(file.run_decision_channel) # empty! not defined on channels in earlier julia versions
            end

            result_task = Threads.@spawn begin
                try
                    evaluate!(file, output; showprogress, options, markdown, chunk_callback)
                finally
                    put!(file.run_decision_channel, :evaluate_finished)
                end
            end

            # block until a decision is reached
            decision = take!(file.run_decision_channel)

            # :forceclose might have been set from another task
            if decision === :forceclose
                close!(server, file.path) # this is in the same task, so reentrant lock allows access
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

struct NoFileEntryError <: Exception
    path::String
end

struct FileBusyError <: Exception
    path::String
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
                return borrow_file!(f, server, apath; optionally_create)
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
            Malt.stop(file.worker)
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
            # but if not, we request a forced close via the run decision channel that
            # is being waited for in `run!` function
        else
            put!(file.run_decision_channel, :forceclose)
            t = time()
            while Malt.isrunning(file.worker)
                timeout = 10
                (time() - t) > timeout && error(
                    "Force close was requested but worker was still running after $timeout seconds.",
                )
                sleep(0.1)
            end
        end
    finally
        lock_attained && unlock(file.lock)
    end
    return
end

json_reader(str) = JSON3.read(str, Any)
yaml_reader(str) = YAML.load(str)

function Parser()
    parser = CommonMark.Parser()
    CommonMark.enable!(parser, CommonMark.FrontMatterRule(; yaml = yaml_reader))
    return parser
end

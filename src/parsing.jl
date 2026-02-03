# Notebook parsing and chunk extraction.

"""
    yaml_reader(str)

Parse YAML string content.
"""
yaml_reader(str) = YAML.load(str)

"""
    Parser()

Create a CommonMark parser with frontmatter support.
"""
function Parser()
    parser = CommonMark.Parser()
    CommonMark.enable!(parser, CommonMark.FrontMatterRule(; yaml = yaml_reader))
    return parser
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

"""
    extract_cell_options(source; file, line)

Parse YAML cell options from `#| ` prefixed lines in source.
"""
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

"""
    compute_line_file_lookup(nlines, path, source_ranges)

Build a lookup table mapping line numbers to source file locations.
"""
function compute_line_file_lookup(nlines, path, source_ranges)
    nlines_ranges = maximum(r -> r.lines.stop, source_ranges) # number of lines reported might be different from the markdown string due to quarto bugs
    lookup = fill((; file = "unknown", line = 0), nlines_ranges)
    for source_range in source_ranges
        file::String = something(source_range.file, "unknown")
        for line in source_range.lines
            source_line = line - first(source_range.lines) + source_range.source_line
            lookup[line] = (; file, line = source_line)
        end
    end
    return lookup
end
function compute_line_file_lookup(nlines, path, source_ranges::Nothing)
    return [(; file = path, line) for line = 1:nlines]
end

"""
    raw_text_chunks(file::File)

Return a vector of raw markdown and code chunks from `file` ready for evaluation
by `evaluate_raw_cells!`.
"""
raw_text_chunks(file::File, ::Nothing; source_ranges = nothing) = raw_text_chunks(file.path)
raw_text_chunks(file::File, markdown::String; source_ranges = nothing) =
    raw_markdown_chunks_from_string(file.path, markdown; source_ranges)

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
    endswith(file.path, ".qmd") ? raw_markdown_chunks(file.path) :
    throw(ArgumentError("file is not a quarto markdown file: $(file.path)"))
raw_markdown_chunks(path::String) =
    raw_markdown_chunks_from_string(path, read(path, String))

function raw_markdown_chunks_from_string(
    path::String,
    markdown::String;
    source_ranges = nothing,
)
    raw_chunks = []
    source_code_hash = hash(VERSION)
    pars = Parser()
    ast = pars(markdown; source = path)
    file_fromtmatter = CommonMark.frontmatter(ast)
    source_code_hash = hash(file_fromtmatter, source_code_hash)
    source_lines = collect(eachline(IOBuffer(markdown)))
    terminal_line = 1

    line_file_lookup = compute_line_file_lookup(length(source_lines), path, source_ranges)

    code_cells = false
    for (node, enter) in ast
        if enter &&
           (is_julia_toplevel(node) || is_python_toplevel(node) || is_r_toplevel(node))
            code_cells = true
            line = node.sourcepos[1][1]
            md = join(source_lines[terminal_line:(line-1)], "\n")
            push!(
                raw_chunks,
                (; type = :markdown, source = md, line_file_lookup[terminal_line]...),
            )
            if contains(md, r"`{(?:julia|python|r)} ")
                source_code_hash = hash(md, source_code_hash)
            end
            terminal_line = node.sourcepos[2][1] + 1

            # currently, the only execution-relevant cell option is `eval` which controls if a code block is executed or not.
            # this option could in the future also include a vector of line numbers, which knitr supports.
            # all other options seem to be quarto-rendering related, like where to put figure captions etc.
            source = node.literal
            cell_options = extract_cell_options(source; line_file_lookup[line]...)
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
                (;
                    type = :code,
                    language = language,
                    source,
                    line_file_lookup[line]...,
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
            (; type = :markdown, source = md, line_file_lookup[terminal_line]...),
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
            (; type = :markdown, source = "", file = path, line = terminal_line),
        )
    end

    frontmatter = _recursive_merge(default_frontmatter(), file_fromtmatter)

    return source_code_hash, raw_chunks, frontmatter
end

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

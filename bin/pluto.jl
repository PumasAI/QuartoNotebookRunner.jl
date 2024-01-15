import JuliaFormatter
import Logging
import MacroTools
import Pluto

const ADMONITION_REGEX = r"!!! (note|warning|tip)"

function convert_notebooks(dir)
    dir = abspath(dir)
    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(file, ".jl")
                path = joinpath(root, file)
                content = read(path, String)
                if contains(content, "### A Pluto.jl notebook ###")
                    convert_notebook(path)
                end
            end
        end
    end
end

function remove_qmds(dir)
    dir = abspath(dir)
    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(file, ".qmd")
                path = joinpath(root, file)
                @info "removing" path
                rm(path)
            end
        end
    end
end

function convert_notebook(path)
    @info "converting notebook" path
    nb = Logging.with_logger(Logging.NullLogger()) do
        Pluto.load_notebook(path; disable_writing_notebook_files = true)
    end
    buffer = IOBuffer()

    title = first(splitext(basename(path)))
    println(
        buffer,
        """
        ---
        title: "$(title)"
        format:
          html:
            embed-resources: true
            self-contained-math: true
        toc: true
        fig-format: svg
        fig-width: 8
        fig-height: 6
        ---
        """,
    )

    for cell_id in nb.cell_order
        cell = nb.cells_dict[cell_id]
        try
            ex = Meta.parseall(cell.code)
            if Meta.isexpr(ex, :toplevel)
                if !isempty(ex.args) && MacroTools.@capture ex.args[end] @md_str(str_)
                    source = ex.args[end].args[end]
                    source = contains(source, ADMONITION_REGEX) ? format_markdown(source) : source
                    println(buffer, source)
                else
                    print_code(buffer, cell.code)
                end
            else
                @warn "weird cell..." cell_id path
                print_code(buffer, cell.code)
            end
        catch error
            isa(error, Meta.ParseError) || rethrow(error)
            @warn "parse error" error cell_id path
            print_code(buffer, cell.code)
        end
    end
    seekstart(buffer)

    qmd = joinpath(dirname(path), replace(basename(path), ".jl" => ".qmd"))
    @info "writing" qmd
    open(qmd, "w") do io
        # Normalise file endings to include exactly one newline at the end of the file.
        write(io, rstrip(String(take!(buffer))))
        println(io)
    end
end

function print_code(buffer, code)
    println(buffer, "```{julia}")
    println(buffer, format_code(code))
    println(buffer, "```")
    println(buffer)
end

function format_markdown(text)
    # Convert Pluto admonitions to Quarto callouts
    replacements = Dict("note" => "callout-note", "warning" => "callout-caution", "tip" => "callout-tip")
    lines = split(text, '\n')
    new_text = ""
    in_block = false

    for line in lines
        begin_block = match(ADMONITION_REGEX, line)
        if begin_block !== nothing
            if in_block
                new_text = new_text[1:end-1] * ":::\n\n"
            end
            new_text *= ":::{.$(replacements[begin_block.captures[1]])}\n"
            in_block = true
        elseif in_block && !startswith(line, r"^[^\s]")
            new_text *= replace(replace(String(line), r"^ {4,8}" => ""), r"^\t+" => "") * "\n"
        elseif in_block
            new_text = new_text[1:end-1] * ":::\n\n" * line * "\n"
            in_block = false
        else
            new_text *= line * "\n"
        end
    end

    if in_block
        new_text = new_text[1:end-1] * ":::\n\n"
    end

    return new_text
end

function format_code(code)
    # Drop `begin`/`let` and `end` if they start and end the code block.
    stripped = strip(code)
    if startswith(stripped, "begin") && endswith(stripped, "end")
        stripped = String(strip(stripped[7:end-3]))
        return JuliaFormatter.format_text(stripped; indent = 4)
    elseif startswith(stripped, "let") && endswith(stripped, "end")
        stripped = String(strip(stripped[5:end-3]))
        return JuliaFormatter.format_text(stripped; indent = 4)
    else
        return JuliaFormatter.format_text(String(stripped); indent = 4)
    end
end

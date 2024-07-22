function render(
    code::AbstractString,
    file::AbstractString,
    line::Integer,
    cell_options::AbstractDict = Dict{String,Any}();
    inline::Bool = false,
)
    # This records whether the outermost cell is an expandable cell, which we
    # then return to the server so that it can decide whether to treat the cell
    # results it gets back as an expansion or not. We can't decide this
    # statically since expansion depends on whether the runtime type of the cell
    # output is `is_expandable` or not. Recursive calls to `_render_thunk` don't
    # matter to the server, it's just the outermost cell that matters.
    is_expansion_ref = Ref(false)
    result = Base.@invokelatest(
        collect(
            _render_thunk(code, cell_options, is_expansion_ref; inline) do
                Base.@invokelatest include_str(
                    NotebookState.notebook_module(),
                    code;
                    file,
                    line,
                    cell_options,
                )
            end,
        )
    )
    return (result, is_expansion_ref[])
end

# Recursively render cell thunks. This might be an `include_str` call,
# which is the starting point for a source cell, or it may be a
# user-provided thunk that comes from a source cell with `expand` set
# to `true`.
function _render_thunk(
    thunk::Base.Callable,
    code::AbstractString,
    cell_options::AbstractDict = Dict{String,Any}(),
    is_expansion_ref::Ref{Bool} = Ref(false);
    inline::Bool,
)
    NotebookState.CELL_OPTIONS[] = cell_options
    captured, display_results = with_inline_display(thunk, cell_options)

    # Attempt to expand the cell. This requires the cell result to have a method
    # defined for the `QuartoNotebookWorker.expand` function. We only attempt to
    # run expansion if the cell didn't error. Cell expansion can itself error,
    # so we need to catch that and return an error cell if that's the case.
    expansion = nothing
    is_expansion = false
    if !captured.error
        try
            expansion = Base.@invokelatest expand(captured.value)
            is_expansion = _is_expanded(captured.value, expansion)
        catch error
            backtrace = catch_backtrace()
            return ((;
                code = "", # an expanded cell that errored can't have returned code
                cell_options = Dict{String,Any}(), # or options
                results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}(),
                display_results,
                output = captured.output,
                error = string(typeof(error)),
                backtrace = collect(
                    eachline(IOBuffer(clean_bt_str(true, backtrace, error))),
                ),
            ),)
        end
        # Track in this side-channel whether the cell is an expansion or not.
        is_expansion_ref[] = is_expansion
    end

    if is_expansion
        # A cell expansion with `expand` might itself also contain
        # cells that expand to multiple cells, so we need to flatten
        # the results to a single list of cells before passing back
        # to the server. Cell expansion is recursive.
        return _flatmap(expansion) do cell
            wrapped = function ()
                return QuartoNotebookWorker.Packages.IOCapture.capture(
                    cell.thunk;
                    rethrow = InterruptException,
                    color = true,
                )
            end
            # **The recursive call:**
            return Base.@invokelatest _render_thunk(
                wrapped,
                cell.code,
                cell.options;
                inline,
            )
        end
    else
        results = Base.@invokelatest render_mimetypes(
            REPL.ends_with_semicolon(code) ? nothing : captured.value,
            cell_options;
            inline,
        )
        # Wrap the `NamedTuple` in a `Tuple` to avoid the `NamedTuple`
        # being flattened into just it's values when passed into
        # `flatmap` and `collect`.
        return ((;
            code,
            cell_options,
            results,
            display_results,
            output = captured.output,
            error = captured.error ? string(typeof(captured.value)) : nothing,
            backtrace = collect(
                eachline(
                    IOBuffer(
                        clean_bt_str(captured.error, captured.backtrace, captured.value),
                    ),
                ),
            ),
        ),)
    end
end

# Setting the `helpmode` module isn't an option on Julia 1.6 so we need to
# manually replace `Main` with the module we want.
function _helpmode(code::AbstractString, mod::Module)
    ex = REPL.helpmode(code)
    return postwalk(ex) do x
        return x == Main ? mod : x
    end
end

function _process_code(
    mod::Module,
    code::AbstractString;
    filename::AbstractString,
    lineno::Integer,
)
    help_regex = r"^\s*\?"
    if startswith(code, help_regex)
        code = String(chomp(replace(code, help_regex => ""; count = 1)))
        ex = _helpmode(code, mod)

        # helpmode embeds object references to `stdout` into the
        # expression, but since we are capturing the output it refers to
        # a different stream. We need to replace the first `stdout`
        # reference with `:stdout` and remove the argument from the
        # other call so that it uses the redirected one.
        ex.args[2] = :stdout
        deleteat!(ex.args[end].args, 3)

        return Expr(:toplevel, ex)
    end

    shell_regex = r"^\s*;"
    if startswith(code, shell_regex)
        code = chomp(replace(code, shell_regex => ""; count = 1))
        ex = :($(Base).@cmd($code))

        # Force the line numbering of macroexpansion errors to match the
        # location in the notebook cell where the shell command was
        # written.
        ex.args[2] = LineNumberNode(lineno, filename)

        return Expr(:toplevel, :($(Base).run($ex)), nothing)
    end

    pkg_regex = r"^\s*\]"
    if startswith(code, pkg_regex)
        code = String(chomp(replace(code, pkg_regex => ""; count = 1)))
        return Expr(
            :toplevel,
            :(
                let printed = $(Pkg).REPLMode.PRINTED_REPL_WARNING[]
                    $(Pkg).REPLMode.PRINTED_REPL_WARNING[] = true
                    try
                        $(Pkg).REPLMode.do_cmd($(Pkg).REPLMode.MiniREPL(), $code)
                    finally
                        $(Pkg).REPLMode.PRINTED_REPL_WARNING[] = printed
                    end
                end
            ),
        )
    end

    return _parseall(code; filename, lineno)
end

function include_str(
    mod::Module,
    code::AbstractString;
    file::AbstractString,
    line::Integer,
    cell_options::AbstractDict,
)
    loc = LineNumberNode(line, Symbol(file))
    try
        ast = _process_code(mod, code; filename = file, lineno = line)
        @assert Meta.isexpr(ast, :toplevel)
        # Note: IO capturing combines stdout and stderr into a single
        # `.output`, but Jupyter notebook spec appears to want them
        # separate. Revisit this if it causes issues.
        return Packages.IOCapture.capture(;
            rethrow = InterruptException,
            color = true,
            io_context = _io_context(cell_options),
        ) do
            result = nothing
            line_and_ex = Expr(:toplevel, loc, nothing)
            try
                for ex in ast.args
                    if ex isa LineNumberNode
                        loc = ex
                        line_and_ex.args[1] = ex
                        continue
                    end
                    # Wrap things to be eval'd in a :toplevel expr to carry line
                    # information as part of the expr.
                    line_and_ex.args[2] = ex
                    for transform in REPL.repl_ast_transforms
                        line_and_ex = Base.@invokelatest transform(line_and_ex)
                    end
                    result = Core.eval(mod, line_and_ex)
                    run_post_eval_hooks()
                end
            catch error
                run_post_eval_hooks()
                run_post_error_hooks()
                rethrow(error)
            end
            return result
        end
    catch err
        if err isa Base.Meta.ParseError
            return (;
                result = err,
                output = "",
                error = true,
                backtrace = catch_backtrace(),
            )
        else
            rethrow(err)
        end
    end
end

# passing our module removes Main.Notebook noise when printing types etc.
function with_context(io::IO, cell_options = Dict{String,Any}())
    return IOContext(io, _io_context(cell_options)...)
end

function _io_context(cell_options = Dict{String,Any}())
    return [
        :module => NotebookState.notebook_module(),
        :limit => true,
        # This allows a `show` method implementation to check for
        # metadata that may be of relevance to it's rendering. For
        # example, if a `typst` table is rendered with a caption
        # (available in the `cell_options`) then we need to adjust the
        # syntax that is output via the `QuartoNotebookRunner/typst`
        # show method to switch between `markdown` and `code` "mode".
        #
        # TODO: perhaps preprocess the metadata provided here rather
        # than just passing it through as-is.
        :QuartoNotebookRunner => (; cell_options, options = NotebookState.OPTIONS[]),
    ]
end

function clean_bt_str(is_error::Bool, bt, err, prefix = "", mimetype = false)
    is_error || return UInt8[]

    # Only include the first encountered `top-level scope` in the
    # backtrace, since that's the actual notebook code. The rest is just
    # the worker code.
    bt = Base.scrub_repl_backtrace(bt)
    top_level = findfirst(x -> x.func === Symbol("top-level scope"), bt)
    bt = bt[1:something(top_level, length(bt))]

    if mimetype
        non_worker = findfirst(x -> contains(String(x.file), @__FILE__), bt)
        bt = bt[1:max(something(non_worker, length(bt)) - 3, 0)]
    end

    buf = IOBuffer()
    buf_context = with_context(buf)
    print(buf_context, prefix)
    Base.showerror(buf_context, err)
    Base.show_backtrace(buf_context, bt)

    return take!(buf)
end


_mimetype_wrapper(@nospecialize(value)) = value

abstract type WrapperType end

# Required methods to avoid `show` method ambiguity errors.
Base.show(io::IO, w::WrapperType) = Base.show(io, w.value)
Base.show(io::IO, m::MIME, w::WrapperType) = Base.show(io, m, w.value)
Base.show(io::IO, m::MIME"text/plain", w::WrapperType) = Base.show(io, m, w.value)
Base.showable(mime::MIME, w::WrapperType) = Base.showable(mime, w.value)


# for inline code chunks, `inline` should be set to `true` which causes "text/plain" output like
# what you'd get from `print` (Strings without quotes) and not from `show("text/plain", ...)`
function render_mimetypes(value, cell_options; inline::Bool = false)
    # Intercept objects prior to rendering so that we can wrap specific
    # types in our own `WrapperType` to customised rendering instead of
    # what the package defines itself.
    value = _mimetype_wrapper(value)

    to_format = NotebookState.OPTIONS[]["format"]["pandoc"]["to"]

    result = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}()
    # Some output formats that we want to write to need different
    # handling of valid MIME types. Currently `docx` and `typst`. When
    # we detect that the `to` format is one of these then we select a
    # different set of MIME types to try and render the value as. The
    # `QuartoNotebookRunner/*` MIME types are unique to this package and
    # are how package authors can hook into the display system used here
    # to allow their types to be rendered correctly in different
    # outputs.
    #
    # NOTE: We may revise this approach at any point in time and these
    # should be considered implementation details until officially
    # documented.
    mime_groups = Dict(
        "docx" => [
            "QuartoNotebookRunner/openxml",
            "text/plain",
            "text/markdown",
            "text/latex",
            "image/svg+xml",
            "image/png",
        ],
        "typst" => [
            "QuartoNotebookRunner/typst",
            "text/plain",
            "text/markdown",
            "text/latex",
            "image/svg+xml",
            "image/png",
        ],
    )
    mimes = if inline
        ["text/plain", "text/markdown"]
    else
        get(mime_groups, to_format) do
            [
                "text/plain",
                "text/markdown",
                "text/html",
                "text/latex",
                "image/svg+xml",
                "image/png",
                "application/pdf",
                "application/json",
            ]
        end
    end
    for mime in mimes
        if showable(mime, value)
            buffer = IOBuffer()
            try
                if inline && mime == "text/plain"
                    Base.@invokelatest print(with_context(buffer, cell_options), value)
                else
                    Base.@invokelatest show(with_context(buffer, cell_options), mime, value)
                end
            catch error
                backtrace = catch_backtrace()
                result[mime] = (;
                    error = true,
                    data = clean_bt_str(
                        true,
                        backtrace,
                        error,
                        "Error showing value of type $(typeof(value))\n",
                        true,
                    ),
                )
                continue
            end
            # See whether the current MIME type needs to be handled
            # specially and embedded in a raw markdown block and whether
            # we should skip attempting to render any other MIME types
            # to may match.
            skip_other_mimes, new_mime, new_buffer = _transform_output(mime, buffer)
            # Only send back the bytes, we do the processing of the
            # data on the parent process where we have access to
            # whatever packages we need, e.g. working out the size
            # of a PNG image or converting a JSON string to an
            # actual JSON object that avoids double serializing it
            # in the notebook output.
            result[new_mime] = (; error = false, data = take!(new_buffer))
            skip_other_mimes && break
        end
    end
    return result
end
render_mimetypes(value::Nothing, cell_options; inline::Bool = false) =
    Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}()


# Our custom MIME types need special handling. They get rendered to
# `text/markdown` blocks with the original content wrapped in a raw
# markdown block. MIMEs that don't match just get passed through.
function _transform_output(mime::String, buffer::IO)
    mapping = Dict(
        "QuartoNotebookRunner/openxml" => (true, "text/markdown", "openxml"),
        "QuartoNotebookRunner/typst" => (true, "text/markdown", "typst"),
    )
    if haskey(mapping, mime)
        (skip_other_mimes, mime, raw) = mapping[mime]
        io = IOBuffer()
        println(io, "```{=$raw}")
        println(io, rstrip(read(seekstart(buffer), String)))
        println(io, "```")
        return (skip_other_mimes, mime, io)
    else
        return (false, mime, buffer)
    end
end

struct PNG
    object::Vector{UInt8}
end
Base.show(io::IO, ::MIME"image/png", png::PNG) = write(io, png.object)

struct SVG
    object::Vector{UInt8}
end
function Base.show(io::IO, ::MIME"image/svg+xml", svg::SVG)
    r = Random.randstring()
    text = String(svg.object)
    text = replace(text, "id=\"glyph" => "id=\"glyph$r")
    text = replace(text, "href=\"#glyph" => "href=\"#glyph$r")
    print(io, text)
end

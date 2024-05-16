function render(
    code::AbstractString,
    file::AbstractString,
    line::Integer,
    cell_options::AbstractDict = Dict{String,Any}(),
)
    return Base.@invokelatest(
        collect(
            _render_thunk(code, cell_options) do
                Base.@invokelatest include_str(
                    NotebookState.notebook_module(),
                    code;
                    file,
                    line,
                )
            end,
        )
    )
end

# Recursively render cell thunks. This might be an `include_str` call,
# which is the starting point for a source cell, or it may be a
# user-provided thunk that comes from a source cell with `expand` set
# to `true`.
function _render_thunk(
    thunk::Base.Callable,
    code::AbstractString,
    cell_options::AbstractDict = Dict{String,Any}(),
)
    captured, display_results = with_inline_display(thunk, cell_options)
    if get(cell_options, "expand", false) === true
        if captured.error
            return ((;
                code = "", # an expanded cell that errored can't have returned code
                cell_options = Dict{String,Any}(), # or options
                results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}(),
                display_results,
                output = captured.output,
                error = string(typeof(captured.value)),
                backtrace = collect(
                    eachline(
                        IOBuffer(
                            clean_bt_str(
                                captured.error,
                                captured.backtrace,
                                captured.value,
                            ),
                        ),
                    ),
                ),
            ),)
        else
            function invalid_return_value_cell(
                errmsg;
                code = "",
                cell_options = Dict{String,Any}(),
            )
                return ((;
                    code,
                    cell_options,
                    results = Dict{String,@NamedTuple{error::Bool, data::Vector{UInt8}}}(),
                    display_results,
                    output = captured.output,
                    error = "Invalid return value for expanded cell",
                    backtrace = collect(eachline(IOBuffer(errmsg))),
                ),)
            end

            if !(Base.@invokelatest Base.isiterable(typeof(captured.value)))
                return invalid_return_value_cell(
                    """
                    Return value of a cell with `expand: true` is not iterable.
                    The returned value must iterate objects that each have a `thunk`
                    property which contains a function that returns the cell output.
                    Instead, the returned value was:
                    $(repr(captured.value))
                    """,
                )
            end

            # A cell expansion with `expand` might itself also contain
            # cells that expand to multiple cells, so we need to flatten
            # the results to a single list of cells before passing back
            # to the server. Cell expansion is recursive.
            return _flatmap(enumerate(captured.value)) do (i, cell)

                code = _getproperty(cell, :code, "")
                options = _getproperty(Dict{String,Any}, cell, :options)

                if !(code isa String)
                    return invalid_return_value_cell(
                        """
                        While iterating over the elements of the return value of a cell with
                        `expand: true`, a value was found at position $i which has a `code` property
                        that is not of the expected type `String`. The value was:
                        $(repr(cell.code))
                        """,
                    )
                end

                if !(options isa Dict{String})
                    return invalid_return_value_cell(
                        """
                        While iterating over the elements of the return value of a cell with
                        `expand: true`, a value was found at position $i which has a `options` property
                        that is not of the expected type `Dict{String}`. The value was:
                        $(repr(cell.options))
                        """;
                        code,
                    )
                end

                if !hasproperty(cell, :thunk)
                    return invalid_return_value_cell(
                        """
                        While iterating over the elements of the return value of a cell with
                        `expand: true`, a value was found at position $i which does not have a
                        `thunk` property. Every object in the iterator returned from an expanded
                        cell must have a property `thunk` with a function that returns
                        the output of the cell.
                        The object without a `thunk` property was:
                        $(repr(cell))
                        """;
                        code,
                        cell_options = options,
                    )
                end

                if !(cell.thunk isa Base.Callable)
                    return invalid_return_value_cell(
                        """
                        While iterating over the elements of the return value of a cell with
                        `expand: true` a value was found at position $i which has a `thunk`
                        property that is not a function of type `Base.Callable`.
                        Every object in the iterator returned from an expanded
                        cell must have a property `thunk` with a function that returns
                        the output of the cell. Instead, the returned value was:
                        $(repr(cell.thunk))
                        """;
                        code,
                        cell_options = options,
                    )
                end

                wrapped = function ()
                    return QuartoNotebookWorker.Packages.IOCapture.capture(
                        cell.thunk;
                        rethrow = InterruptException,
                        color = true,
                    )
                end

                # **The recursive call:**
                return Base.@invokelatest _render_thunk(wrapped, code, options)
            end
        end
    else
        results = Base.@invokelatest render_mimetypes(
            REPL.ends_with_semicolon(code) ? nothing : captured.value,
            cell_options,
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


function include_str(mod::Module, code::AbstractString; file::AbstractString, line::Integer)
    loc = LineNumberNode(line, Symbol(file))

    # handle REPL modes
    if code[1] == '?'
        code = "Core.eval(Main.REPL, Main.REPL.helpmode(\"$(code[2:end])\"))"
    elseif code[1] == ';'
        code = "Base.repl_cmd(`$(code[2:end])`, stdout)"
    elseif code[1] == ']'
        code = "Pkg.REPLMode.PRINTED_REPL_WARNING[]=true; Pkg.REPLMode.do_cmd(Pkg.REPLMode.MiniREPL(),\"$(code[2:end])\")"
    end

    try
        ast = _parseall(code, filename = file, lineno = line)
        @assert Meta.isexpr(ast, :toplevel)
        # Note: IO capturing combines stdout and stderr into a single
        # `.output`, but Jupyter notebook spec appears to want them
        # separate. Revisit this if it causes issues.
        return Packages.IOCapture.capture(; rethrow = InterruptException, color = true) do
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
                        line_and_ex = transform(line_and_ex)
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
    return IOContext(
        io,
        :module => NotebookState.notebook_module(),
        :color => true,
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
    )
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


function render_mimetypes(value, cell_options)
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
    mimes = get(mime_groups, to_format) do
        [
            "text/plain",
            "text/markdown",
            "text/html",
            "text/latex",
            "image/svg+xml",
            "image/png",
            "application/json",
        ]
    end
    for mime in mimes
        if showable(mime, value)
            buffer = IOBuffer()
            try
                Base.@invokelatest show(with_context(buffer, cell_options), mime, value)
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
render_mimetypes(value::Nothing, cell_options) =
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

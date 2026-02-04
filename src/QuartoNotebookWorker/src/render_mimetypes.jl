# MIME type rendering.

_mimetype_wrapper(@nospecialize(value)) = value

abstract type WrapperType end

# Required methods to avoid `show` method ambiguity errors.
Base.show(io::IO, w::WrapperType) = Base.show(io, w.value)
Base.show(io::IO, m::MIME, w::WrapperType) = Base.show(io, m, w.value)
Base.show(io::IO, m::MIME"text/plain", w::WrapperType) = Base.show(io, m, w.value)
Base.showable(mime::MIME, w::WrapperType) = Base.showable(mime, w.value)


# for inline code chunks, `inline` should be set to `true` which causes "text/plain" output like
# what you'd get from `print` (Strings without quotes) and not from `show("text/plain", ...)`
function render_mimetypes(
    value,
    cell_options;
    inline::Bool = false,
    only::Union{String,Nothing} = nothing,
)
    # Intercept objects prior to rendering so that we can wrap specific
    # types in our own `WrapperType` to customised rendering instead of
    # what the package defines itself.
    value = _mimetype_wrapper(value)

    options = NotebookState.OPTIONS[]
    to_format = rget(options, ("format", "pandoc", "to"), nothing)

    result = Dict{String,WorkerIPC.MimeResult}()
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
        if showable(mime, value) && _matching_mimetype(mime, only)
            buffer = IOBuffer()
            try
                if inline && mime == "text/plain"
                    Base.@invokelatest __print_barrier__(
                        with_context(buffer, cell_options, inline),
                        value,
                    )
                else
                    Base.@invokelatest __show_barrier__(
                        with_context(buffer, cell_options, inline),
                        mime,
                        value,
                    )
                end
            catch error
                backtrace = catch_backtrace()
                result[mime] = WorkerIPC.MimeResult(
                    mime,
                    true,
                    clean_bt_str(
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
            result[new_mime] = WorkerIPC.MimeResult(new_mime, false, take!(new_buffer))
            skip_other_mimes && break
        end
    end
    return result
end
render_mimetypes(value::Nothing, cell_options; inline::Bool = false, only = nothing) =
    Dict{String,WorkerIPC.MimeResult}()

_matching_mimetype(mime::String, only::Nothing) = true
_matching_mimetype(mime::String, only::String) = mime == only

# These methods are used to mark the location within stacktraces that marks the
# end of user-code. This is used by the `clean_bt_str` function to strip
# stackframes un-related to user code. No inlining is essential here.
@noinline __show_barrier__(io, mime, value) = Base.show(io, mime, value)
@noinline __print_barrier__(io, value) = Base.print(io, value)

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

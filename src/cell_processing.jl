# Cell source and output processing.

"""
    source_lines(s; keep=false)

Split source string into lines.
"""
source_lines(s::AbstractString; keep = false) = collect(eachline(IOBuffer(s); keep = keep))

"""
    json_reader(str)

Parse JSON string content.
"""
json_reader(str) = JSON3.read(str, Any)

"""
    process_cell_source(source, cell_options=Dict())

Process cell source into lines, optionally prepending YAML cell options.
"""
function process_cell_source(source::AbstractString, cell_options::Dict = Dict())
    lines = source_lines(source; keep = true)
    if !isempty(lines)
        lines[end] = rstrip(lines[end])
    end
    if isempty(cell_options)
        return lines
    else
        yaml = YAML.write(cell_options)
        return vcat(String["#| $line" for line in source_lines(yaml; keep = true)], lines)
    end
end

"""
    strip_cell_options(source)

Remove `#|` prefixed lines from cell source.
"""
function strip_cell_options(source::AbstractString)
    lines = source_lines(source; keep = true)
    keep_from = something(findfirst(!startswith("#|"), lines), 1)
    join(lines[keep_from:end])
end

"""
    wrap_with_r_boilerplate(code)

Wrap code for execution via RCall.
"""
function wrap_with_r_boilerplate(code)
    """
    @isdefined(RCall) && RCall isa Module && Base.PkgId(RCall).uuid == Base.UUID("6f49c342-dc21-5d91-9882-a32aef131414") || error("RCall must be imported to execute R code cells with QuartoNotebookRunner")
    RCall.rcopy(RCall.R\"\"\"
    $code
    \"\"\")
    """
end

"""
    wrap_with_python_boilerplate(code)

Wrap code for execution via PythonCall.
"""
function wrap_with_python_boilerplate(code)
    """
    Main.QuartoNotebookWorker.py\"\"\"
    $code
    \"\"\"
    """
end

"""
    transform_source(chunk)

Transform cell source based on language, wrapping R/Python code appropriately.
"""
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

# Escape special markdown characters per CommonMark spec (backslash escapes)
_escape_markdown(s::AbstractString) = replace(s, r"([\\`*_{}[\]()#+\-.!|])" => s"\\\1")
_escape_markdown(bytes::Vector{UInt8}) = _escape_markdown(String(bytes))

"""
    process_inline_results(dict)

Process inline code evaluation results, returning markdown or escaped plaintext.
"""
function process_inline_results(dict::Dict{String,WorkerIPC.MimeResult})
    isempty(dict) && return ""
    # A reduced set of mimetypes are available for inline use.
    for (mime, func) in ["text/markdown" => String, "text/plain" => _escape_markdown]
        if haskey(dict, mime)
            r = dict[mime]
            if r.error
                error("Error rendering inline code: $(String(r.data))")
            else
                return func(r.data)
            end
        end
    end
    error("No valid mimetypes found in inline code results.")
end

"""
    process_results(dict::Dict{String,WorkerIPC.MimeResult})

Process the results of a remote evaluation into a dictionary of mimetypes to
values. We do here rather than in the worker because we don't want to have to
define additional functions in the worker and import `Base64` there. The worker
just has to provide bytes.
"""
function process_results(dict::Dict{String,WorkerIPC.MimeResult})
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
            traceback = source_lines(String(payload.data))
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

"""
    png_image_metadata(bytes; phys_correction=true)

Extract width and height metadata from PNG bytes, optionally correcting
for physical pixel dimensions.
"""
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

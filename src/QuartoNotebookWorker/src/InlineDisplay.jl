# InlineDisplay type.

# Intercepts all calls to `display` within the cell and passes the
# objects instead to our own `InlineDisplay` display that is pushed onto
# the display stack. The `InlineDisplay` just reuses the same
# `render_mimetypes` function as "normal" cell output does.
struct InlineDisplay <: AbstractDisplay
    queue::Vector{Any}
    cell_options::Dict

    function InlineDisplay(cell_options::Dict)
        new(Any[], cell_options)
    end
end

function Base.display(d::InlineDisplay, x)
    push!(d.queue, Base.@invokelatest render_mimetypes(x, d.cell_options))
    return nothing
end
Base.displayable(::InlineDisplay, m::MIME) = true

function with_inline_display(f, cell_options)
    inline_display = InlineDisplay(cell_options)
    pushdisplay(inline_display)
    try
        return f(), inline_display.queue
    finally
        popdisplay(inline_display)
    end
end

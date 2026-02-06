# Package hooks and Revise support

revise_hook() = _revise_hook(nothing)
_revise_hook(::Any) = nothing

function rget(dict, keys, default)
    value = dict
    for key in keys
        if haskey(value, key)
            value = value[key]
        else
            return default
        end
    end
    return value
end

function _figure_metadata()
    ctx = NotebookState.current_context()
    options = ctx === nothing ? Dict{String,Any}() : ctx.options

    fig_width_inch = rget(options, ("format", "execute", "fig-width"), nothing)
    fig_height_inch = rget(options, ("format", "execute", "fig-height"), nothing)
    fig_format = rget(options, ("format", "execute", "fig-format"), nothing)
    fig_dpi = rget(options, ("format", "execute", "fig-dpi"), nothing)

    return (; fig_width_inch, fig_height_inch, fig_format, fig_dpi)
end

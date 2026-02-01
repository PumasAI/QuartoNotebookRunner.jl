function refresh!(path, original_options, options = original_options)
    # Set working directory based on cwd option (from execute-dir) or default
    # to notebook directory.
    cd(something(options["cwd"], dirname(path)))
    task_local_storage()[:SOURCE_PATH] = path

    # Reset back to the original project environment if it happens to
    # have changed during cell evaluation.
    NotebookState.reset_active_project!()

    NotebookState.define_notebook_module!()

    # Rerun the package loading hooks if the options have changed.
    if NotebookState.OPTIONS[] != options
        NotebookState.OPTIONS[] = options
        run_package_loading_hooks()
    else
        NotebookState.OPTIONS[] = options
    end

    # Run package refresh hooks every time.
    run_package_refresh_hooks()

    return nothing
end

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
    options = NotebookState.OPTIONS[]

    fig_width_inch = rget(options, ("format", "execute", "fig-width"), nothing)
    fig_height_inch = rget(options, ("format", "execute", "fig-height"), nothing)
    fig_format = rget(options, ("format", "execute", "fig-format"), nothing)
    fig_dpi = rget(options, ("format", "execute", "fig-dpi"), nothing)

    return (; fig_width_inch, fig_height_inch, fig_format, fig_dpi)
end

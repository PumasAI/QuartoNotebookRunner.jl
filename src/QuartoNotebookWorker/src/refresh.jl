function refresh!(path, original_options, options = original_options)
    task_local_storage()[:SOURCE_PATH] = path
    
    # We check the `execute-dir` key in the options,
    if haskey(options, "project") && haskey(options["project"], "execute-dir")
        ed = options["project"]["execute-dir"]
        if ed == "file"
            cd(dirname(path))
        elseif ed == "project"
            # TODO: this doesn't seem right. How does one get the root path of the project here?
            # Maybe piggyback on `options` with some ridiculous identifier?
            # We can't rely on `pwd`, because the notebook can change that.
            if isfile(NotebookState.PROJECT[])
                cd(dirname(NotebookState.PROJECT[]))
            elseif isdir(NotebookState.PROJECT[])
                cd(NotebookState.PROJECT[])
            else
                @warn "Project path not found: $(NotebookState.PROJECT[])"
            end
        else
            error("Quarto only accepts `file` or `project` as arguments to `execute-dir`, got `$ed`.")
        end
    else
        # Current directory should always start out as the directory of the
        # notebook file, which is not necessarily right initially if the parent
        # process was started from a different directory to the notebook.
        cd(dirname(path))
    end

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

function refresh!(path, original_options, options = original_options)
    # Current directory should always start out as the directory of the
    # notebook file, which is not necessarily right initially if the parent
    # process was started from a different directory to the notebook.
    cd(dirname(path))

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

function _figure_metadata()
    options = NotebookState.OPTIONS[]

    fig_width_inch = options["format"]["execute"]["fig-width"]
    fig_height_inch = options["format"]["execute"]["fig-height"]
    fig_format = options["format"]["execute"]["fig-format"]
    fig_dpi = options["format"]["execute"]["fig-dpi"]

    if fig_format == "retina"
        fig_format = "svg"
    end

    return (; fig_width_inch, fig_height_inch, fig_format, fig_dpi)
end

function refresh!(path, options = OPTIONS[])
    # Current directory should always start out as the directory of the
    # notebook file, which is not necessarily right initially if the parent
    # process was started from a different directory to the notebook.
    cd(dirname(path))

    # Reset back to the original project environment if it happens to
    # have changed during cell evaluation.
    PROJECT == Base.active_project() || Pkg.activate(PROJECT; io = devnull)

    # Attempt to clear up as much of the previous workspace as possible
    # by setting all the variables to `nothing`. This is a bit of a
    # hack, but since if a `Function` gets defined in a `Module` then it
    # gets rooted in the global MethodTable and stops the `Module` from
    # being GC'd, apparently. This should cover most use-cases, e.g. a
    # user creates a massive array in a cell, and then reruns it
    # numerous times. So long as it isn't a `const` we should be able to
    # clear it to `nothing` and GC the actual data.
    mod = getfield(Main, :Notebook)
    for name in names(mod; all = true)
        if isdefined(mod, name) && !Base.isdeprecated(mod, name)
            try
                Base.setproperty!(mod, name, nothing)
            catch error
                @debug "failed to undefine:" name error
            end
        end
    end
    # Force GC to run to try and clean up the variables that are now set
    # to `nothing`.
    GC.gc()

    # Replace the module with a new one, so that redefinition of consts
    # works between notebook runs.
    Core.eval(Main, :(Notebook = $(Module(nameof(mod)))))

    # Ensure that `Pkg` is always available in the notebook so that users
    # can immediately activate a project environment if they want to.
    Core.eval(getfield(Main, :Notebook), :(import Main: Pkg, ojs_define))
    # Custom `include` and `eval` implementation to match behaviour of the REPL.
    Core.eval(getfield(Main, :Notebook), :(import Main.NotebookInclude: include, eval))

    # Rerun the package loading hooks if the options have changed.
    if OPTIONS[] != options
        OPTIONS[] = options
        run_package_loading_hooks()
    else
        OPTIONS[] = options
    end

    # Run package refresh hooks every time.
    run_package_refresh_hooks()

    return nothing
end

function _figure_metadata()
    options = OPTIONS[]

    fig_width_inch = options["format"]["execute"]["fig-width"]
    fig_height_inch = options["format"]["execute"]["fig-height"]
    fig_format = options["format"]["execute"]["fig-format"]
    fig_dpi = options["format"]["execute"]["fig-dpi"]

    if fig_format == "retina"
        fig_format = "svg"
    end

    return (; fig_width_inch, fig_height_inch, fig_format, fig_dpi)
end

module QuartoNotebookWorkerMakieExt

import QuartoNotebookWorker
import ..Makie

function configure()
    fm = QuartoNotebookWorker._figure_metadata()
    # only change Makie theme if sizes are set, if only one is set, pick an aspect ratio of 4/3
    # which might be more user-friendly than throwing an error
    if fm.fig_width_inch !== nothing || fm.fig_height_inch !== nothing
        _width_inch =
            fm.fig_width_inch !== nothing ? fm.fig_width_inch : fm.fig_height_inch * 4 / 3
        _height_inch =
            fm.fig_height_inch !== nothing ? fm.fig_height_inch : fm.fig_width_inch / 4 * 3

        # Convert inches to CSS pixels or device-independent pixels which Makie
        # uses as the base unit for its plots when used with default settings.
        fig_width = _width_inch * 96
        fig_height = _height_inch * 96

        pkgid = Base.PkgId(Makie)
        if QuartoNotebookWorker._pkg_version(pkgid) < v"0.20"
            Makie.update_theme!(; resolution = (fig_width, fig_height))
        else
            Makie.update_theme!(; size = (fig_width, fig_height))
        end
    end
end

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        configure()
        QuartoNotebookWorker.add_package_loading_hook!(configure)
    end
end

end

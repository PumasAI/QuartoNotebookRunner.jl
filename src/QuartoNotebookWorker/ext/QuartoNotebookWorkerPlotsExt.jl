module QuartoNotebookWorkerPlotsExt

import QuartoNotebookWorker
import Plots

function configure()
    fm = QuartoNotebookWorker._figure_metadata()
    # Convert inches to CSS pixels or device-independent pixels.
    # Empirically, an SVG is saved by Plots with width and height taken directly as CSS pixels (without unit specified)
    # so the conversion with the 96 factor would be correct in that setting.
    # However, with bitmap export they don't quite seem to follow that, where with 100dpi
    # you get an image whose size (with rounding error) matches the numbers set for size while
    # this should happen with 96. But we cannot solve that discrepancy here. So we just forward
    # the values as given.

    if fm.fig_width_inch !== nothing || fm.fig_height_inch !== nothing
        # if only width or height is set, pick an aspect ratio of 4/3
        # which might be more user-friendly than throwing an error
        _width_inch =
            fm.fig_width_inch !== nothing ? fm.fig_width_inch : fm.fig_height_inch * 4 / 3
        _height_inch =
            fm.fig_height_inch !== nothing ? fm.fig_height_inch : fm.fig_width_inch / 4 * 3
        fig_width_px = _width_inch * 96
        fig_height_px = _height_inch * 96
        size_kwargs = Dict{Symbol,Any}(:size => (fig_width_px, fig_height_px))
    else
        size_kwargs = Dict{Symbol,Any}()
    end

    if fm.fig_dpi !== nothing
        dpi_kwargs = Dict{Symbol,Any}(:dpi => fm.fig_dpi)
    else
        dpi_kwargs = Dict{Symbol,Any}()
    end

    if (QuartoNotebookWorker._pkg_version(pkgid) < v"1.28.1") && (fm.fig_format == "pdf")
        Plots.gr(; size_kwargs..., fmt = :png, dpi_kwargs...)
    else
        Plots.gr(; size_kwargs..., fmt = fm.fig_format, dpi_kwargs...)
    end
    return nothing
end

function __init__()
    configure()
    QuartoNotebookWorker.add_package_loading_hook!(configure)
end

end

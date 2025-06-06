module QuartoNotebookWorkerCairoMakieExt

import QuartoNotebookWorker
import CairoMakie

function configure()
    fm = QuartoNotebookWorker._figure_metadata()
    if fm.fig_dpi !== nothing
        kwargs = Dict{Symbol,Any}(
            :px_per_unit => fm.fig_dpi / 96,
            :pt_per_unit => 0.75, # this is the default in Makie, too, because 1 CSS px == 0.75 pt
        )
    else
        kwargs = Dict{Symbol,Any}()
    end
    kwargs[:type] = if fm.fig_format in ("pdf", "svg")
        "svg" # enables both pdf and svg, simpler for backends like typst and latex which prefer one
    else
        "png" # all other fig formats are bitmaps, "retina" is handled via dpi settings
    end
    CairoMakie.activate!(; kwargs...)

    return nothing
end

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        configure()
        QuartoNotebookWorker.add_package_refresh_hook!(configure)
    end
end

end

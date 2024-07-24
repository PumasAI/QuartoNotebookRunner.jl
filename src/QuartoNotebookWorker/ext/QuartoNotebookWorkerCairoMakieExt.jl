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
    if fm.fig_format == "pdf"
        kwargs[:type] = "png"
    else
        if isa(fm.fig_format, AbstractString)
            kwargs[:type] = fm.fig_format
        end
    end
    CairoMakie.activate!(; kwargs...)

    return nothing
end

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        configure()
        QuartoNotebookWorker.add_package_loading_hook!(configure)
    end
end

end

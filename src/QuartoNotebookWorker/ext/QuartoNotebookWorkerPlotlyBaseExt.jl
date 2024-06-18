module QuartoNotebookWorkerPlotlyBaseExt

import QuartoNotebookWorker
import PlotlyBase

struct PlotlyBasePlotWithoutRequireJS
    plot::PlotlyBase.Plot
end

struct PlotlyRequireJSConfig end

const FIRST_PLOT_DISPLAYED = Ref(false)

function QuartoNotebookWorker.expand(p::PlotlyBase.Plot)

    plotcell = QuartoNotebookWorker.Cell(PlotlyBasePlotWithoutRequireJS(p))

    # Quarto expects that the require.js preamble which Plotly needs to function
    # comes in its own cell, which will then be hoisted into the HTML page header.
    # So we cannot have that preamble concatenated with every plot's HTML content.
    # Instead, e keep track whether a Plotly plot is the first per notebook, and in that
    # case have it expand into the preamble cell and the plot cell. If it's not the
    # first time, we expand only into the plot cell.
    cells = if !FIRST_PLOT_DISPLAYED[]
        [QuartoNotebookWorker.Cell(PlotlyRequireJSConfig()), plotcell]
    else
        [plotcell]
    end

    FIRST_PLOT_DISPLAYED[] = true

    return cells
end

function Base.show(io::IO, ::MIME"text/html", p::PlotlyBasePlotWithoutRequireJS)
    # We want to embed only the minimum markup needed to render the
    # plotlyjs plots, otherwise a full HTML page is generated for every
    # plot which does not render correctly in our context.
    # "require-loaded" means that we pass the require.js preamble ourselves.
    PlotlyBase.to_html(io, p.plot; include_plotlyjs = "require-loaded", full_html = false)
end

Base.show(io::IO, M::MIME, p::PlotlyBasePlotWithoutRequireJS) = show(io, M, p.plot)
Base.show(io::IO, m::MIME"text/plain", p::PlotlyBasePlotWithoutRequireJS) =
    show(io, m, p.plot)
Base.showable(M::MIME, p::PlotlyBasePlotWithoutRequireJS) = showable(M, p.plot)

function Base.show(io::IO, ::MIME"text/html", ::PlotlyRequireJSConfig)
    print(io, PlotlyBase._requirejs_config())
end

function reset_first_plot_displayed_flag!()
    FIRST_PLOT_DISPLAYED[] = false
end

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        QuartoNotebookWorker.add_package_refresh_hook!(reset_first_plot_displayed_flag!)
    end
end

end

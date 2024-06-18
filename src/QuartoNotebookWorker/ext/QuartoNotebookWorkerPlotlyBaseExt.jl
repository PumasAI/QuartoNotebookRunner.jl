module QuartoNotebookWorkerPlotlyBaseExt

import QuartoNotebookWorker
import PlotlyBase

QuartoNotebookWorker._mimetype_wrapper(p::PlotlyBase.Plot) = PlotlyBasePlot(p)

struct PlotlyBasePlot <: QuartoNotebookWorker.WrapperType
    value::PlotlyBase.Plot
end

function Base.show(io::IO, ::MIME"text/html", wrapper::PlotlyBasePlot)
    # We want to embed only the minimum markup needed to render the
    # plotlyjs plots, otherwise a full HTML page is generated for every
    # plot which does not render correctly in our context.
    PlotlyBase.to_html(io, wrapper.value; include_plotlyjs = "require-loaded", full_html = false)
end

end

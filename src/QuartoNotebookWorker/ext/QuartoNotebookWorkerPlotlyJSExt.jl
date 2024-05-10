module QuartoNotebookWorkerPlotlyJSExt

import QuartoNotebookWorker
import PlotlyJS

QuartoNotebookWorker._mimetype_wrapper(p::PlotlyJS.SyncPlot) = PlotlyJSSyncPlot(p)

struct PlotlyJSSyncPlot <: QuartoNotebookWorker.WrapperType
    value::PlotlyJS.SyncPlot
end

function Base.show(io::IO, ::MIME"text/html", wrapper::PlotlyJSSyncPlot)
    # We want to embed only the minimum markup needed to render the
    # plotlyjs plots, otherwise a full HTML page is generated for every
    # plot which does not render correctly in our context.
    PlotlyJS.PlotlyBase.to_html(
        io,
        wrapper.value.plot;
        include_plotlyjs = "require",
        full_html = false,
    )
end

end

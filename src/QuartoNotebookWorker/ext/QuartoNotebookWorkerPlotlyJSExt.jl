module QuartoNotebookWorkerPlotlyJSExt

import QuartoNotebookWorker
import PlotlyJS

QuartoNotebookWorker.expand(p::PlotlyJS.SyncPlot) = QuartoNotebookWorker.expand(p.plot)

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        QuartoNotebookWorker.extension_loaded!(@__MODULE__)
    end
end

end

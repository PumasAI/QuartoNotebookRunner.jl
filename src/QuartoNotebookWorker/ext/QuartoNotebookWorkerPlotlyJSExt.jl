module QuartoNotebookWorkerPlotlyJSExt

import QuartoNotebookWorker
import ..PlotlyJS

QuartoNotebookWorker.expand(p::PlotlyJS.SyncPlot) = QuartoNotebookWorker.expand(p.plot)

end

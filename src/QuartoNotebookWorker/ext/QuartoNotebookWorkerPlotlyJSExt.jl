module QuartoNotebookWorkerPlotlyJSExt

import QuartoNotebookWorker
import PlotlyJS

QuartoNotebookWorker._mimetype_wrapper(p::PlotlyJS.SyncPlot) = QuartoNotebookWorker._mimetype_wrapper(p.plot)

end

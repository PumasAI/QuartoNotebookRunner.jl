module QuartoNotebookWorkerJSON3Ext

import QuartoNotebookWorker
import JSON3

QuartoNotebookWorker._json3_write(::Nothing) = JSON3.write

end

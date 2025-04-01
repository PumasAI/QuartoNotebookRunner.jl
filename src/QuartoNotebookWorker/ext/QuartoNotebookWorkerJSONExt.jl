module QuartoNotebookWorkerJSONExt

import QuartoNotebookWorker
import JSON

QuartoNotebookWorker._json_write(::Nothing) = JSON.print

end

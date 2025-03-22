module QuartoNotebookWorkerTablesExt

import QuartoNotebookWorker
import Tables

QuartoNotebookWorker.__istable(::Nothing, x) = Tables.istable(x)
QuartoNotebookWorker.__rows(::Nothing, x) = collect(Tables.rows(x))

end

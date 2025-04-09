module QuartoNotebookWorkerTablesExt

import QuartoNotebookWorker
import Tables

# _ojs_convert() will use _ojs_rows() to convert objects
# that support Tables.istable() interface
QuartoNotebookWorker._istable(::Nothing, obj) = Tables.istable(obj)
QuartoNotebookWorker._ojs_rows(::Nothing, obj) = NamedTuple.(Tables.rows(obj))

end

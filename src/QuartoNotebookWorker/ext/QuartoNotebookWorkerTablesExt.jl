module QuartoNotebookWorkerTablesExt

import QuartoNotebookWorker
import Tables: istable, rows

# _ojs_convert() returns Tables.rows() iterator
# for objects supporting Tables.istable() interface
QuartoNotebookWorker._has_trait(::Val{:table}, obj) = Tables.istable(obj)
QuartoNotebookWorker._ojs_convert(::Val{:table}, obj) = Tables.rows(obj)

end
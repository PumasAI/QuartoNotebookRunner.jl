module QuartoNotebookWorkerDataFramesTablesExt

import QuartoNotebookWorker
import DataFrames
import Tables

QuartoNotebookWorker._ojs_convert(df::DataFrames.AbstractDataFrame) = Tables.rows(df)

end

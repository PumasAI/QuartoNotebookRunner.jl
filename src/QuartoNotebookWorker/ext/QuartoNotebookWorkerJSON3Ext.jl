module QuartoNotebookWorkerJSON3Ext

import QuartoNotebookWorker
import JSON3

QuartoNotebookWorker._json3_write(::Nothing) = JSON3.write

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        QuartoNotebookWorker.extension_loaded!(@__MODULE__)
    end
end

end

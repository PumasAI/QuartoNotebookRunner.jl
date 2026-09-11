module QuartoNotebookWorkerJSONExt

import QuartoNotebookWorker
import JSON

QuartoNotebookWorker._json_write(::Nothing) = JSON.print

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        QuartoNotebookWorker.extension_loaded!(@__MODULE__)
    end
end

end

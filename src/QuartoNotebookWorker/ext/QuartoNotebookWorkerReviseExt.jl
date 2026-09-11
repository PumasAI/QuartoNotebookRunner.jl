module QuartoNotebookWorkerReviseExt

import Revise
import QuartoNotebookWorker as QNW

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 0
        QNW.extension_loaded!(@__MODULE__)
    end
    @debug "extension has been loaded" Revise QuartoNotebookWorker
end

function QNW._revise_hook(::Nothing)
    isempty(Revise.revision_queue) || Base.invokelatest(Revise.revise; throw = true)
    return nothing
end

end
